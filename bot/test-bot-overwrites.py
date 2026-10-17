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
import _pyguard  # noqa: F401  (first: Python 3.10 or newer, #2276)
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
# The join card is a file (#2341).
ATTACH_FILES = 1 << 15

# Every mode that shuts @everyone out of one of the three. Only public does
# not, and a public channel needs nothing for the bot.
RESTRICTED = ('read', 'open', 'membersread', 'hold', 'staff', 'pathfind', 'gm',
              'gmrules')
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
    # The running set Build-Discord.py prints the invite for, which holds
    # the three and the thread ones as well.
    bot_role = Role('Thornswood Bot', 7, 60, B.RUN_PERMISSIONS)
    g.roles.append(bot_role)
    roles = dict((r.name, r) for r in g.roles)

    bare = types.SimpleNamespace(default_role=g.default_role, me=None,
                                 roles=g.roles)

    for catname, specs in B.PLAN:
        cat = None
        # The same modes on_ready gives a category it makes.
        cmode = {'Staff': 'staff', 'Testing': 'pathfind', 'The Holds': 'hold',
                 'Gamemasters': 'gm',
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

        # ------------------------------- one channel's own extra roles --
        #
        # Patrick locked the Live smoke session on 1 October to Owner, Dev
        # and Lead GM. pathfind grants STAFF and Playtester, and the lead
        # gamemaster role is in neither, so somebody holding only that one
        # passed bot.py's admin check and could not see #test-tasks. It is
        # on that channel's own line in PLAN rather than in the mode,
        # because the mode is what every pathfind channel uses.
        tasks = [s for _c, specs in B.PLAN for s in specs
                 if s.get('key') == 'TESTS'][0]
        others = [s for _c, specs in B.PLAN for s in specs
                  if s.get('mode') == 'pathfind' and s.get('key') != 'TESTS']
        yes('the Live smoke channel names the lead gamemaster role on its own '
            'line, both ways it has been spelled',
            tuple(tasks.get('extra_roles') or ()) == ('Lead Gamemaster', 'Lead GM'))
        yes('  and no other pathfind channel was quietly widened with it',
            others and not any(s.get('extra_roles') for s in others))

        # Lead Gamemaster is in ROLES since 2 October, where the live role
        # list has it, so the server carries it already and _named finds that
        # one. It is still looked up by name rather than assumed, which is what
        # lets the other spelling be passed over below.
        lead = roles['Lead Gamemaster']
        boss = Member(8, [lead])
        named = dict(roles)

        ch = Channel(g, 'test-tasks', 'text',
                     ow=B.overwrites(bare, 'pathfind', named, None, B.BOT_NEEDS,
                                     tasks.get('extra_roles')))
        yes('a new Live smoke channel lets a Lead Gamemaster in',
            gets_in(resolve(g, boss, ch)))
        yes('  and still shuts out somebody who is only a Member',
            not resolve(g, somebody, ch).view_channel)
        yes('  and somebody not yet approved',
            not resolve(g, newcomer, ch).view_channel)
        yes('  and testers and staff are in it as they always were',
            gets_in(resolve(g, Member(9, [named['Playtester']]), ch))
            and gets_in(resolve(g, Member(10, [named['Moderator']]), ch)))

        plain = Channel(g, 'test-results', 'text',
                        ow=B.overwrites(bare, 'pathfind', named))
        yes('and the other pathfind channel is unchanged: a Lead Gamemaster '
            'who is nothing else does not see it',
            not resolve(g, boss, plain).view_channel)

        # The channel made before the role existed, or made by hand. Same
        # reason keep_bot exists.
        extra = getattr(B, 'keep_extra', None)
        yes('there is a way to let them into a channel that already exists',
            extra is not None)
        if extra is not None:
            was = Channel(g, 'test-tasks', 'text',
                          ow=B.overwrites(bare, 'pathfind', named))
            g.calls = []
            quiet(extra(was, tasks, named))
            yes('a Live smoke channel already there is written once, for the '
                'one role it was missing',
                [c[0] for c in g.calls] == ['set_permissions']
                and g.calls[0][2] is lead)
            yes('  and a Lead Gamemaster sees, posts and reads there afterwards',
                gets_in(resolve(g, boss, was)))
            yes('  and nobody else gained anything',
                not resolve(g, somebody, was).view_channel
                and not resolve(g, newcomer, was).view_channel)

            g.calls = []
            quiet(extra(was, tasks, named))
            yes('the same channel again is not written to at all', g.calls == [])

            g.calls = []
            quiet(extra(Channel(g, 'test-results', 'text',
                                ow=B.overwrites(bare, 'pathfind', named)),
                        {'name': 'test-results'}, named))
            yes('a channel with no extra roles is never touched by it',
                g.calls == [])

            # Only the spelling the server carries. The other one is passed
            # over rather than created or guessed at.
            g.calls = []
            quiet(extra(Channel(g, 'test-tasks', 'text',
                                ow=B.overwrites(bare, 'pathfind', named)),
                        tasks, named))
            yes('a role name the server has not got is passed over, not made',
                len(g.calls) == 1
                and not [c for c in g.calls if c[0] == 'create_role'])

            B.CHECK = True
            g.calls = []
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                asyncio.run(extra(Channel(g, 'test-tasks', 'text',
                                          ow=B.overwrites(bare, 'pathfind', named)),
                                  tasks, named))
            B.CHECK = False
            yes('-Check says it would let them in and changes nothing',
                g.calls == [] and 'would change' in buf.getvalue())

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

    # ------------------------------- the join card's channel (#2341) --
    #
    # The bot's start on 12 Oct: "cannot post in #welcome-travelers ... the
    # bot is missing Attach Files there". The card is a file. The channel's
    # overwrite for the bot named only the three, so whether it could attach
    # was down to its role's server-wide bits and @everyone's overwrite there,
    # which a build with Administrator cannot see. Either way round, the
    # bot's own overwrite in that channel has to say it.
    join_spec = [s for _c, specs in B.PLAN for s in specs
                 if s['name'] == 'welcome-travelers'][0]
    yes('the plan gives the bot Attach Files in #welcome-travelers and only '
        'there, of the channels it posts in',
        'attach_files' in B.bot_needs(join_spec) and
        not [s for _c, specs in B.PLAN for s in specs
             if s is not join_spec and 'attach_files' in B.bot_needs(s)])
    o = B.overwrites(g, join_spec['mode'], roles, None, B.bot_needs(join_spec)).get(me)
    yes('a new #welcome-travelers gives the bot the three and Attach Files, '
        'and denies nothing',
        o is not None and o.pair()[0].value == WANT | ATTACH_FILES
        and o.pair()[1].value == 0)

    if keep is not None:
        B.CHECK = False
        del B.failed[:]
        # Two ways the live channel can keep the file out, both measured off
        # resolve(): the bot's role without Attach Files and @everyone without
        # it either, or @everyone's overwrite there denying it.
        no_attach = Role('Thornswood Bot', 7, 60,
                         B.RUN_PERMISSIONS & ~ATTACH_FILES)
        bare_role = Role('@everyone', 1, 0, B.PLAIN.value & ~ATTACH_FILES)
        cases = []
        g2, roles2, people2, _n2, _l2 = live_server()
        g2.default_role = bare_role
        g2.me = Member(424242, [no_attach])
        bare2 = types.SimpleNamespace(default_role=g2.default_role, me=None,
                                      roles=g2.roles)
        cases.append(('its role and @everyone without Attach Files', g2,
                      Channel(g2, 'welcome-travelers', 'text',
                              ow=B.overwrites(bare2, 'open', roles2))))
        g3, roles3, people3, _n3, _l3 = live_server()
        bare3 = types.SimpleNamespace(default_role=g3.default_role, me=None,
                                      roles=g3.roles)
        ow3 = B.overwrites(bare3, 'open', roles3)
        ow3[g3.default_role].update(attach_files=False)
        cases.append(('@everyone\'s overwrite there denying Attach Files', g3,
                      Channel(g3, 'welcome-travelers', 'text', ow=ow3)))
        g4, roles4, _p4, _n4, _l4 = live_server()
        g4.default_role = Role('@everyone', 1, 0, B.PLAIN.value & ~ATTACH_FILES)
        g4.me = Member(424242, [Role('Thornswood Bot', 7, 60,
                                     B.RUN_PERMISSIONS & ~ATTACH_FILES)])
        cases.append(('a channel open to everybody, and a role without Attach '
                      'Files', g4, Channel(g4, 'welcome-travelers', 'text')))
        for what, gx, ch in cases:
            mex = gx.me
            # As the #455 run left a gated channel: the bot's own three.
            if ch.ow:
                ch.ow[mex] = discord.PermissionOverwrite(
                    view_channel=True, send_messages=True,
                    read_message_history=True)
            folk = [Member(5, [r for r in gx.roles if r.name == 'Member']),
                    Member(6, [])]
            before = dict((p, resolve(gx, p, ch).value) for p in folk)
            yes('#welcome-travelers with ' + what + ': the bot sees and posts '
                'there but cannot attach the card, which is what its start '
                'logged (the problem, measured)',
                gets_in(resolve(gx, mex, ch)) and not resolve(gx, mex, ch).attach_files)
            gx.calls = []
            quiet(keep(ch, B.bot_needs(join_spec)))
            p = resolve(gx, mex, ch)
            yes('  after it the bot sees, posts, reads and attaches the card there',
                gets_in(p) and p.attach_files)
            yes('  written once, the bot\'s own overwrite and nothing else',
                [(c[0], c[2]) for c in gx.calls] == [('set_permissions', mex)])
            yes('  and nobody else gained anything',
                all(resolve(gx, q, ch).value == before[q] for q in folk))
            gx.calls = []
            quiet(keep(ch, B.bot_needs(join_spec)))
            yes('  and a second run writes nothing', gx.calls == [])

        # A channel the plan asks nothing extra of is still left alone when
        # it is open to everybody: the change is the join channel's own.
        ch = Channel(g4, 'general', 'text')
        g4.calls = []
        quiet(keep(ch))
        yes('an ordinary channel open to everybody is still never touched',
            g4.calls == [] and g4.me not in ch.ow)

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
    tickets = by_name['tickets-and-applications']
    yes('  and in #tickets-and-applications it could open a ticket thread but '
        'not write in it, even with the running set on its role',
        not resolve(g, me, tickets).send_messages_in_threads)

    said = run(g, True)
    yes('-Check writes nothing to any channel',
        not [c for c in g.calls if c[0] == 'set_permissions'])
    yes('  and says it would let the bot into #staff-general',
        '#staff-general lets the bot in' in said)
    yes('  and the run did not stop part way', 'stopped:' not in said)

    said = run(g, False)
    every_write = [c for c in g.calls if c[0] == 'set_permissions']
    # The one write that is not the bot's is Lead Gamemaster on #test-tasks,
    # the role that channel names on its own line. Everything about the bot is
    # measured without it, and the block further down measures it on its own.
    theirs = [c for c in every_write if c[2] is not me]
    writes = [c for c in every_write if c[2] is me]
    wrote = [c[1] for c in writes]
    yes('the build did not stop part way', 'stopped:' not in said)
    yes('nothing was made, because everything was already there',
        not [c for c in g.calls if c[0].startswith('create_')])
    yes('every write was the bot\'s own overwrite, bar the one role a channel '
        'names for itself',
        [(c[1].name, c[2].name) for c in theirs] ==
        [('test-tasks', 'Lead Gamemaster')])

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
    p = resolve(g, me, tickets)
    yes('without Administrator the bot opens a private thread in '
        '#tickets-and-applications and writes the ticket into it',
        p.create_private_threads and p.send_messages_in_threads)
    o = tickets.ow.get(me)
    yes('  and its overwrite there is the three plus Create Private Threads and '
        'Send Messages in Threads, and denies nothing',
        o is not None and o.pair()[0].value == WANT | (1 << 36) | (1 << 38)
        and o.pair()[1].value == 0)
    join = by_name['welcome-travelers']
    o = join.ow.get(me)
    yes('its overwrite in #welcome-travelers is the three plus Attach Files, '
        'for the join card, and denies nothing (#2341)',
        o is not None and o.pair()[0].value == WANT | ATTACH_FILES
        and o.pair()[1].value == 0)
    yes('  and every other channel it writes gets the three and nothing more',
        all(c[1].ow[me].pair()[0].value == WANT for c in writes
            if c[1] is not tickets and c[1] is not join))
    yes('the build ends without the invite when the client cannot say which '
        'application it is, rather than a link with no id in it',
        'oauth2/authorize' not in said)

    said = run(g, False)
    yes('a second run writes nothing, so it asks nothing of Discord once '
        'Administrator is gone',
        not [c for c in g.calls if c[0] == 'set_permissions'])

    # ------------------------- the whole build, with a Lead Gamemaster --
    #
    # The channels on the live server were made before the role was named on
    # any of them, so the extra roles are the only thing that reaches one.
    # Everything else about the run must be the same as above: one more write,
    # on one channel, for one role.
    g, roles, people, news, loose = live_server()
    me = g.me
    lead = roles['Lead Gamemaster']
    boss = Member(8, [lead])
    by_name = dict((c.name, c) for c in g.categories + g.channels if c is not news)
    tasks = by_name['test-tasks']
    everything = g.categories + g.channels
    before_them = dict(((p, c), resolve(g, p, c).value)
                       for p in people for c in everything)

    yes('before the run, a Lead Gamemaster cannot see #test-tasks (the gap, '
        'measured)', not resolve(g, boss, tasks).view_channel)

    said = run(g, False)
    writes = [c for c in g.calls if c[0] == 'set_permissions']
    theirs = [c for c in writes if c[2] is lead]
    yes('the build did not stop part way', 'stopped:' not in said)
    yes('after it, a Lead Gamemaster sees, posts and reads in #test-tasks',
        gets_in(resolve(g, boss, tasks)))
    yes('  written once, on that channel and no other',
        len(theirs) == 1 and theirs[0][1] is tasks)
    yes('  and #test-findings is not one of them, so pathfind is not widened '
        'everywhere', not resolve(g, boss, by_name['test-findings']).view_channel)
    yes('  nor is any staff channel or the one made by hand, because the role '
        'is not in STAFF',
        not resolve(g, boss, by_name['staff-general']).view_channel
        and not resolve(g, boss, news).view_channel)
    yes('  and the holds it does see are HOLD_STAFF\'s doing, which is what '
        'that list is for, and no hold was written to',
        resolve(g, boss, by_name['whiterun']).view_channel
        and not [c for c in theirs if c[1] is by_name['whiterun']])
    yes('  and every other write was still the bot\'s own overwrite',
        all(c[2] is me for c in writes if c[2] is not lead))
    yes('  and nobody else gained a thing: not a Member, not somebody not yet '
        'approved, in any channel (%d)' % len(everything),
        all(resolve(g, p, c).value == before_them[(p, c)]
            for p in people for c in everything))
    yes('nothing failed', not B.failed)

    said = run(g, False)
    yes('and a second run with that role there writes nothing either',
        not [c for c in g.calls if c[0] == 'set_permissions'])

    # ---------------------------------- the invite a finished build ends on --
    g, roles, people, news, loose = live_server()
    Client.application_id = 123456789012345678
    try:
        said = run(g, False)
        link = ('https://discord.com/oauth2/authorize?client_id=123456789012345678'
                '&scope=bot&permissions=%d' % B.RUN_PERMISSIONS)
        yes('a build with nothing failed ends on the invite with the running set',
            link in said)
        yes('  and on the line saying to untick Administrator on the bot\'s role, '
            'naming it', 'untick Administrator' in said and 'Thornswood Bot' in said
            and said.index('untick Administrator') > said.index(link))
        yes('  and never asks for 8', 'permissions=8&' not in said
            and not said.rstrip().endswith('permissions=8'))
        said = run(g, True)
        yes('-Check does not, because nothing was built',
            'oauth2/authorize' not in said)
        g, roles, people, news, loose = live_server()
        by_name = dict((c.name, c) for c in g.channels)
        by_name['staff-general'].refuse = True
        said = run(g, False)
        yes('nor does a build where something failed, because the run that '
            'fixes it still wants Administrator',
            B.failed and 'oauth2/authorize' not in said)
    finally:
        del Client.application_id

finally:
    shutil.rmtree(TMP, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
