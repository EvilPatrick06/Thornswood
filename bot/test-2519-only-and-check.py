"""
test-2519-only-and-check.py

Issue #2519. A run of the builder approved for one part of the Discord does
that part and nothing else, and -Check says what the same run would do.

On 22 Oct 2026 at 3:59 AM a -Check run for the Gamemasters category, approved
with the Attach Files overwrite on #welcome-travelers, planned far more:
  - 50 role moves, every role after Server Booster, for roles already in
    order: the builder counted places down from its own role, and Server
    Booster, which something else manages and the builder never moves, was
    not where that count put it, so every role after it read one place off;
  - "would write" for all seven read only posts, though a run without -Posts
    leaves them alone;
  - and it MADE the Gamemasters category, because the category step had no
    -Check guard ("made 1").
Plus a hand-made gated channel and two server or channel settings that the
approval did not cover.

What this checks, with Build-Discord.py imported for real under another name
and every guild, role and channel a stand-in that records what would have
been asked of Discord:
  1. role_moves: roles already in the plan's order are not moved, whatever
     sits between them and wherever a managed role is; roles out of order
     are put in order among the places they hold, and a role the plan does
     not name keeps its place;
  2. -Check makes no category, no channel and no webhook, and says would
     make for each;
  3. -Check without -Posts says the posts are left alone and never would
     write; with -Posts it says would write;
  4. DISCORD_ONLY='Gamemasters,welcome-travelers': the category and its
     channels are made, #welcome-travelers gets the bot's Attach Files
     overwrite, and nothing else is asked of Discord: no role made or moved,
     no other channel written, no server setting, no post, no webhook;
  5. a name the plan does not have stops it before Discord is asked.

Never connects to anything. The news webhook file goes to a temporary folder.
"""
import _pyguard  # noqa: F401  (first: Python 3.11 or newer, #2276)
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


spec = importlib.util.spec_from_file_location(
    'build_discord_2519', os.path.join(HERE, 'Build-Discord.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)
discord = B.discord


# ------------------------------------------------------------ stand-ins --
class Role(object):
    def __init__(self, guild, name, position, managed=False):
        self.guild = guild
        self.name = name
        self.id = 1000 + len(guild.roles)
        self.position = position
        self.managed = managed
        self.permissions = discord.Permissions(0)

    async def edit(self, **kw):
        self.guild.calls.append(('role.edit', self.name, kw))
        if 'position' in kw:
            self.guild.move(self, kw['position'])

    def __repr__(self):
        return '<role %s>' % self.name


class Member(object):
    def __init__(self, roles):
        self.id = 424242
        self.roles = list(roles)
        self.top_role = self.roles[-1]


class Channel(object):
    def __init__(self, guild, name, kind, category=None, topic=None, ow=None):
        self.guild = guild
        self.name = name
        self.kind = kind
        self.category = category
        self.topic = topic
        self.ow = dict(ow or {})
        self.channels = []

    @property
    def overwrites(self):
        return dict(self.ow)

    def overwrites_for(self, target):
        o = self.ow.get(target)
        if o is None:
            return discord.PermissionOverwrite()
        a, d = o.pair()
        return discord.PermissionOverwrite.from_pair(a, d)

    async def set_permissions(self, target, overwrite=None, reason=None):
        self.guild.calls.append(('set_permissions', self.name, target))
        a, d = overwrite.pair()
        self.ow[target] = discord.PermissionOverwrite.from_pair(a, d)

    async def edit(self, **kw):
        # A place's overwrites set whole (#3317) are its own call, so a check
        # on topics and settings is not confused with them.
        if 'overwrites' in kw:
            self.guild.calls.append(('overwrites', self.name, kw))
            self.ow = dict(kw['overwrites'])
            return
        self.guild.calls.append(('channel.edit', self.name, kw))

    async def webhooks(self):
        return list(self.guild.hooks)

    async def create_webhook(self, **kw):
        self.guild.calls.append(('create_webhook', self.name, kw))
        return types.SimpleNamespace(name='Thornswood', url='https://example.invalid/hook')

    async def delete(self, **kw):
        self.guild.calls.append(('delete', self.name, kw))

    def __repr__(self):
        return '<#%s>' % self.name


class Guild(object):
    def __init__(self):
        self.id = 1
        self.name = 'Thornswood stand-in'
        self.roles = []
        self.calls = []
        self.categories = []
        self.channels = []
        self.hooks = [types.SimpleNamespace(name='Thornswood', url='https://example.invalid/hook')]
        self.features = ['COMMUNITY']
        self.rules_channel = object()
        self.system_channel = object()
        self.afk_channel = None
        with open(os.path.join(HERE, 'staff-channel.txt'), encoding='utf-8') as f:
            self.staff_updates = types.SimpleNamespace(id=int(f.read().strip()), name='staff-updates')
        self.public_updates_channel = self.staff_updates
        self.safety_alerts_channel = self.staff_updates
        self.default_role = Role(self, '@everyone', 0)
        self.me = None

    def move(self, role, position):
        """Discord's move: the role takes that position and the others keep
           their order around it, numbered 1 up (0 is @everyone)."""
        rest = sorted((r for r in self.roles if r is not role), key=lambda r: r.position)
        rest.insert(max(0, min(len(rest), position - 1)), role)
        for i, r in enumerate(rest):
            r.position = i + 1

    def top_down(self):
        return [r.name for r in sorted(self.roles, key=lambda r: -r.position)]

    async def _made(self, what, name, **kw):
        self.calls.append((what, name))
        ch = Channel(self, name, what, category=kw.get('category'),
                     topic=kw.get('topic'), ow=kw.get('overwrites'))
        self.channels.append(ch)
        if what == 'create_category':
            self.categories.append(ch)
        elif kw.get('category') is not None:
            kw['category'].channels.append(ch)
        return ch

    async def create_role(self, name=None, **kw):
        self.calls.append(('create_role', name))
        r = Role(self, name, 1)
        for o in self.roles:
            o.position += 1
        self.roles.append(r)
        return r

    async def create_category(self, name, **kw):
        return await self._made('create_category', name, **kw)

    async def create_text_channel(self, name, **kw):
        return await self._made('create_text_channel', name, **kw)

    async def create_voice_channel(self, name, **kw):
        return await self._made('create_voice_channel', name, **kw)

    async def create_forum(self, name, **kw):
        return await self._made('create_forum', name, **kw)

    def get_channel(self, cid):
        return self.staff_updates if cid == self.staff_updates.id else None

    async def edit(self, **kw):
        self.calls.append(('guild.edit', None, kw))


class Client(object):
    def __init__(self, guild):
        self.guilds = [guild]

    def get_guild(self, _gid):
        return self.guilds[0]

    async def close(self):
        pass


def live_server(other_between=False):
    """The server as the 22 Oct -Check found it: every role of the plan there
       and in the plan's order, with Server Booster (managed by Discord) sat
       low rather than where counting down from the bot would put it, and a
       role the plan does not name between two of the plan's; every category
       and channel of the plan there except the Gamemasters category; and a
       channel made by hand behind the gate with no overwrite for the bot,
       the way #jukebox is."""
    g = Guild()
    names = [n for n, _c, _h, _p in B.ROLES if n != 'Server Booster']
    if other_between:
        order = ['Thornswood Bot'] + names[:6] + ['Some Other Bot'] + names[6:]
    else:
        order = ['Thornswood Bot'] + names + ['Some Other Bot']
    pos = len(order) + 1
    for n in order:
        g.roles.append(Role(g, n, pos))
        pos -= 1
    g.roles.append(Role(g, 'Server Booster', 1, managed=True))
    g.me = Member([r for r in g.roles if r.name == 'Thornswood Bot'])
    roles = dict((r.name, r) for r in g.roles)
    bare = types.SimpleNamespace(default_role=g.default_role, me=None, roles=g.roles)
    for catname, specs in B.PLAN:
        if catname == 'Gamemasters':
            continue
        cat = None
        if catname:
            cat = Channel(g, catname, 'category')
            g.categories.append(cat)
            g.channels.append(cat)
        for s in specs:
            if not s.get('make', True):
                continue
            want = s['name'].lower().replace(' ', '-') if s['kind'] != 'voice' else s['name']
            ow = B.with_bot(g, B.overwrites(bare, s.get('mode', 'open'), roles, s.get('hold'),
                                            space=s.get('space'), read_extra=s.get('read_extra')),
                            B.bot_needs(s)) if s.get('key') != 'JOIN' else {}
            ch = Channel(g, want, s['kind'], category=cat, topic=s.get('topic'), ow=ow)
            g.channels.append(ch)
            if cat is not None:
                cat.channels.append(ch)
            if s.get('key') == 'AFK':
                g.afk_channel = ch
    around = [c for c in g.categories if c.name == 'Staff'][0]
    juke = Channel(g, 'jukebox', 'text', category=around,
                   ow={g.default_role: discord.PermissionOverwrite(view_channel=False)})
    g.channels.append(juke)
    around.channels.append(juke)
    return g


def run(g, check=False, posts=False, only=''):
    B.CHECK = check
    B.POSTS = posts
    B.PRUNE = False
    B.ROLES_ONLY = False
    B.ONLY = [n.strip() for n in only.split(',') if n.strip()]
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


TMP = tempfile.mkdtemp(prefix='ts-2519-only-')
try:
    B.WEBHOOK_OUT = os.path.join(TMP, 'news-webhook.txt')

    # ---- 1. role_moves --------------------------------------------------
    g = live_server()
    plan = [r for n, _c, _h, _p in B.ROLES for r in g.roles if r.name == n]
    yes('roles already in the plan\'s order are not moved, with Server Booster low',
        B.role_moves(plan) == [])
    top = g.me.top_role.position
    old = [r for i, r in enumerate(plan)
           if not r.managed and r.position != max(1, top - 1 - i)]
    yes('  (counting down from the bot, as before, read %d of them as out of place)' % len(old),
        len(old) > 10)

    g = live_server(other_between=True)
    plan = [r for n, _c, _h, _p in B.ROLES for r in g.roles if r.name == n]
    yes('the same with a role the plan does not name between two of the plan\'s',
        B.role_moves(plan) == [])
    by = dict((r.name, r) for r in g.roles)
    a, b = by['Owner'], by['Moderator']
    a.position, b.position = b.position, a.position
    plan = [r for n, _c, _h, _p in B.ROLES for r in g.roles if r.name == n]
    moves = B.role_moves(plan)
    yes('two roles swapped: only those two are moved', sorted(r.name for r, _ in moves) == ['Moderator', 'Owner'])
    before_other = by['Some Other Bot'].position
    for r, p in moves:
        asyncio.run(r.edit(position=p))
    want = [n for n, _c, _h, _p in B.ROLES if n != 'Server Booster']
    yes('  and afterwards the plan\'s roles are in the plan\'s order',
        [n for n in g.top_down() if n in want] == want)
    yes('  and a role the plan does not name keeps its place',
        by['Some Other Bot'].position == before_other)

    # ---- 2 and 3. -Check ------------------------------------------------
    g = live_server()
    out = run(g, check=True)
    yes('-Check asks Discord for nothing at all', g.calls == [])
    yes('  and makes no category (the 22 Oct -Check made Gamemasters)',
        not any(c[0] == 'create_category' for c in g.calls) and 'made 0' in out)
    yes('  and says it would make the category and each of its channels',
        'category Gamemasters' in out and '#gm-rules' in out and '#gm-discipline' in out and 'voice GM Voice' in out)
    yes('  and plans no role move for roles already in order', 'would move' not in out)
    yes('  without -Posts it never says would write, and says the posts are left alone',
        'would write' not in out and 'left alone' in out and '-Posts rewrites them' in out)
    yes('  and writes down no webhook, though one is there', not os.path.exists(B.WEBHOOK_OUT))
    out = run(live_server(), check=True, posts=True)
    yes('-Check with -Posts says would write', 'would write' in out)

    g = live_server()
    g.hooks = []
    out = run(g, check=True)
    yes('-Check with no news webhook makes none and writes no file',
        not any(c[0] == 'create_webhook' for c in g.calls) and not os.path.exists(B.WEBHOOK_OUT)
        and 'would make' in out and 'news webhook' in out)

    # ---- 4. ONLY --------------------------------------------------------
    g = live_server()
    roles_before = [(r.name, r.position) for r in g.roles]
    out = run(g, only='Gamemasters,welcome-travelers')
    made = [c[1] for c in g.calls if c[0].startswith('create_')]
    yes('ONLY Gamemasters,welcome-travelers makes the category and its eight channels',
        made == ['Gamemasters', 'gm-announcements', 'gm-rules', 'gm-event-plans',
                 'gm-scene-summaries', 'gm-chat', 'gm-suggestions', 'gm-discipline',
                 'GM Voice'])
    perms = [c for c in g.calls if c[0] in ('set_permissions', 'overwrites')]
    wel = [c for c in g.channels if c.name == 'welcome-travelers'][0]
    yes('  gives #welcome-travelers the bot\'s Attach Files overwrite, and writes no other channel',
        [c[1] for c in perms] == ['welcome-travelers'] and wel.overwrites_for(g.me).attach_files is True)
    yes('  makes and moves no role',
        not any(c[0] in ('create_role', 'role.edit') for c in g.calls) and
        [(r.name, r.position) for r in g.roles] == roles_before)
    yes('  changes no server setting, topic, post or webhook',
        not any(c[0] in ('guild.edit', 'channel.edit', 'create_webhook', 'delete') for c in g.calls)
        and 'would write' not in out and not os.path.exists(B.WEBHOOK_OUT))
    yes('  leaves #jukebox alone', not any(c[1] == 'jukebox' for c in g.calls))
    yes('  and says what it was limited to', 'Gamemasters, welcome-travelers. Nothing else was touched' in out)

    g = live_server()
    out = run(g, check=True, only='Gamemasters,welcome-travelers')
    yes('ONLY with -Check asks Discord for nothing, and names the category, its channels and the overwrite',
        g.calls == [] and 'category Gamemasters' in out and
        '#welcome-travelers gets the overwrites of its mode' in out)

    # ---- 5. a name the plan does not have -------------------------------
    try:
        B.plan_for(['Gamemasters', 'gm-lounge'])
        bad = None
    except ValueError as e:
        bad = str(e)
    yes('a name the plan does not have is refused, naming it', bad is not None and 'gm-lounge' in bad)
    yes('a channel named alone is planned in its own category, by itself',
        B.plan_for(['welcome-travelers']) == [(c, [s for s in ss if s['name'] == 'welcome-travelers'])
                                               for c, ss in B.PLAN if any(s['name'] == 'welcome-travelers' for s in ss)])
finally:
    shutil.rmtree(TMP, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
