"""
test-testing-channels.py

Patrick's card of 11 October: the Live smoke checklist is gone from
#test-tasks, and the testing channels are a #test-tasks forum (one thread per
test task, tagged Dev or Main), #test-findings (what #test-results was) and a
#known-issues channel the bot keeps from GitHub issues labelled Dev Findings
or Main Findings.

This holds:

  1. The checklist is gone: no /live-smoke, no session code, no export.
  2. The one-time setup: a preview changes nothing, an apply makes the three
     changes with the old overwrites copied, the forum fallback when Discord
     will not convert a text channel, the archive locked and never deleted,
     and a second run does nothing at all. An apply that stopped half way
     finishes the rest and nothing twice.
  3. A test task is one thread, with its Dev or Main tag, never two for one
     title.
  4. Known issues: one post per open labelled issue, never a second, not
     after a restart and not after a crash between a post and its save;
     closed as completed is struck through and Fixed, closed otherwise says
     so, reopened goes back.

The real bot module is imported. Discord and GitHub are stand-ins that
count what is asked of them. Never connects to anything.
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
for _k in ('TEST_TASK_ROLES', 'LIVE_SMOKE_ADMIN_ROLES', 'GITHUB_TOKEN'):
    os.environ.pop(_k, None)

import discord  # noqa: E402
import bot  # noqa: E402

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


TMP = tempfile.mkdtemp(prefix='thornswood-testing-channels-')
LOGGED = []
bot.log = lambda *a: LOGGED.append(' '.join(str(x) for x in a))


# ------------------------------------------------------------ stand-ins --
class Refused(discord.HTTPException):
    def __init__(self, text='Cannot change the type of this channel'):
        Exception.__init__(self, text)
        self.text = text
        self.code = 50024
        self.status = 400


class Target(object):
    def __init__(self, name, tid):
        self.name = name
        self.id = tid

    def __repr__(self):
        return '<%s>' % self.name


class Category(object):
    def __init__(self, name):
        self.name = name


class Thread(object):
    def __init__(self, name, tags, content):
        self.name = name
        self.applied_tags = tags
        self.content = content
        self.archived = False
        self.mention = '<#%s>' % name


class Channel(object):
    def __init__(self, guild, name, kind, category=None, position=0,
                 overwrites=None, tags=None, convertible=False):
        self.guild = guild
        self.name = name
        self.type = getattr(discord.ChannelType, kind)
        self.category = category
        self.position = position
        self.overwrites = dict(overwrites or {})
        self.available_tags = list(tags or [])
        self.threads = []
        self.convertible = convertible
        self.id = 9000 + len(guild.channels)
        self.sent = []
        guild.channels.append(self)

    def overwrites_for(self, t):
        ow = self.overwrites.get(t)
        if ow is None:
            return discord.PermissionOverwrite()
        a, d = ow.pair()
        return discord.PermissionOverwrite.from_pair(a, d)

    async def edit(self, **k):
        self.guild.calls.append(('edit', self.name, dict(k)))
        if 'type' in k:
            if not self.convertible:
                raise Refused()
            self.type = k['type']
        if 'name' in k:
            self.name = k['name']
        if 'available_tags' in k:
            self.available_tags = list(k['available_tags'])

    async def set_permissions(self, t, overwrite=None, reason=None):
        self.guild.calls.append(('set_permissions', self.name, t))
        self.overwrites[t] = overwrite

    async def create_thread(self, name, content, applied_tags, reason=None):
        self.guild.calls.append(('create_thread', self.name, name))
        th = Thread(name, applied_tags, content)
        self.threads.append(th)
        return th


class Guild(object):
    def __init__(self, gid=1):
        self.id = gid
        self.name = 'Thornswood'
        self.channels = []
        self.calls = []
        self.default_role = Target('@everyone', gid)
        self.me = Target('Thornswood Bot', 2)

    async def create_forum(self, name, category=None, position=0,
                           overwrites=None, topic=None, available_tags=None,
                           reason=None):
        self.calls.append(('create_forum', name))
        return Channel(self, name, 'forum', category, position, overwrites,
                       available_tags)

    async def create_text_channel(self, name, category=None, overwrites=None,
                                  topic=None, reason=None):
        self.calls.append(('create_text_channel', name))
        return Channel(self, name, 'text', category, 0, overwrites)


def OW(**k):
    return discord.PermissionOverwrite(**k)


def server(convertible=False):
    g = Guild()
    testing = Category('Testing')
    play = Target('Playtester', 11)
    staff = Target('Moderator', 12)
    tasks = Channel(g, 'test-tasks', 'text', testing, 4, {
        g.default_role: OW(view_channel=False),
        play: OW(view_channel=True, send_messages=True),
        staff: OW(view_channel=True, send_messages=True, manage_threads=True),
        g.me: OW(view_channel=True, send_messages=True),
    }, convertible=convertible)
    results = Channel(g, 'test-results', 'forum', testing, 3, {
        g.default_role: OW(view_channel=False),
        play: OW(view_channel=True, send_messages=True),
    })
    Channel(g, 'general', 'text')
    return g, tasks, results, play, staff


def pairs(ows):
    return dict((t, tuple(v.value for v in o.pair())) for t, o in ows.items())


def run(c):
    return asyncio.run(c)


# ---------------------------------------------- 1. the checklist is gone --
src = open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
yes('bot.py has no Live smoke code left: no live_smoke function, no '
    'LIVE_SMOKE setting, no /live-smoke group',
    not [n for n in dir(bot) if n.lower().startswith('live_smoke')]
    and 'LIVE_SMOKE_EXPORT' not in src and "name='live-smoke'" not in src
    and 'LiveSmoke' not in src)
yes('and no Pass/Fail/Skip/Fail-known marks or session buttons',
    "'Fail-known'" not in src and "'ls:" not in src)
yes('the export it read is gone from the repository',
    not os.path.exists(os.path.join(HERE, 'live-smoke-discord-export.json')))
names = bot._command_names()
yes('the commands are /close and /test-task, nothing of the checklist (%s)'
    % ', '.join(names),
    'test-task' in names and not [n for n in names if 'smoke' in n])
import inspect  # noqa: E402
hook = inspect.getsource(bot.Thornswood.setup_hook)
yes('setup_hook registers no Live smoke views', 'live_smoke' not in hook)
ready = inspect.getsource(bot.on_ready)
yes('the one-time setup is never run on a normal start',
    'channel_setup' not in ready and 'channel_setup' not in hook)
yes('and the known issues watcher is started once, with the others',
    'watch_known_issues()' in ready)


# -------------------------------------------------------- 2. the setup --
state = os.path.join(TMP, 'channel-setup.json')

g, tasks, results, play, staff = server()
before = pairs(tasks.overwrites)
said = run(bot.channel_setup(g, apply=False, path=state))
yes('a preview asks Discord for nothing and writes no state',
    g.calls == [] and not os.path.exists(state))
text = '\n'.join(said)
yes('  and says each of the three changes it would make',
    'would try to convert #test-tasks' in text
    and 'would make a new forum #test-tasks in Testing' in text
    and 'would rename the old text #test-tasks to #test-tasks-archive' in text
    and 'would rename #test-results to #test-findings' in text
    and 'would make #known-issues in Testing' in text)

said = run(bot.channel_setup(g, apply=True, path=state))
text = '\n'.join(said)
forum = bot._channel_named(g, 'test-tasks', ('forum',))
yes('Discord refusing the conversion is said, and the fallback taken',
    'refused the conversion' in text and forum is not None
    and forum is not tasks)
yes('  the forum is in the same category at the same position',
    forum.category is tasks.category and forum.position == 4)
yes('  with the old channel\'s overwrites copied exactly, as new objects',
    pairs(forum.overwrites) == before
    and not any(forum.overwrites[t] is tasks.overwrites.get(t)
                for t in forum.overwrites))
yes('  and the Dev and Main tags',
    sorted(t.name for t in forum.available_tags) == ['Dev', 'Main'])
yes('the old text channel is kept, renamed test-tasks-archive, not deleted',
    tasks.name == 'test-tasks-archive' and tasks in g.channels
    and not [c for c in g.calls if c[0] == 'delete'])
locked = [t for t in (g.default_role, play, staff)
          if tasks.overwrites[t].send_messages is False
          and tasks.overwrites[t].send_messages_in_threads is False
          and tasks.overwrites[t].create_public_threads is False]
yes('  with sending switched off for @everyone, Playtester and Moderator',
    len(locked) == 3)
yes('  and nothing else about who sees it changed',
    tasks.overwrites[play].view_channel is True
    and tasks.overwrites[staff].manage_threads is True
    and tasks.overwrites[g.default_role].view_channel is False)
yes('  and the bot\'s own overwrite left alone, so it can still read it',
    not [c for c in g.calls if c[0] == 'set_permissions' and c[2] is g.me]
    and tasks.overwrites[g.me].send_messages is True)
yes('#test-results is renamed #test-findings, the same channel and overwrites',
    results.name == 'test-findings'
    and pairs(results.overwrites)[play] == pairs(
        {play: OW(view_channel=True, send_messages=True)})[play])
known = bot._channel_named(g, 'known-issues', ('text',))
yes('#known-issues is made beside it with #test-findings\' overwrites',
    known is not None and known.category is results.category
    and pairs(known.overwrites) == pairs(results.overwrites))
done = json.load(open(state))
yes('the apply is recorded in the state file by server id',
    '1' in done.get('guilds', {}) and done['guilds']['1'].get('done'))

g.calls = []
said = run(bot.channel_setup(g, apply=True, path=state))
yes('a SECOND RUN does nothing at all and says it was already done',
    g.calls == [] and len(said) == 1 and said[0].startswith('already done'))
said = run(bot.channel_setup(g, apply=False, path=state))
yes('  and nor does a preview after it', g.calls == [])

# The conversion, if Discord ever allows it: no new forum and no archive.
state2 = os.path.join(TMP, 'convert.json')
g, tasks, results, play, staff = server(convertible=True)
run(bot.channel_setup(g, apply=True, path=state2))
yes('a channel Discord does convert stays the one channel, no forum made '
    'and nothing archived',
    tasks.type is discord.ChannelType.forum and tasks.name == 'test-tasks'
    and not [c for c in g.calls if c[0] == 'create_forum']
    and not bot._channel_named(g, 'test-tasks-archive'))
yes('  and it is given the Dev and Main tags',
    sorted(t.name for t in tasks.available_tags) == ['Dev', 'Main'])

# Half done: the forum and the rename happened, then it stopped.
state3 = os.path.join(TMP, 'half.json')
g, tasks, results, play, staff = server()
tasks.name = 'test-tasks-archive'
Channel(g, 'test-tasks', 'forum', tasks.category, 4, tasks.overwrites,
        [discord.ForumTag(name='Dev')])
results.name = 'test-findings'
g.calls = []
said = run(bot.channel_setup(g, apply=True, path=state3))
yes('an apply that stopped half way does only what is left: the missing '
    'Main tag and #known-issues',
    [c[0] for c in g.calls] == ['edit', 'create_text_channel']
    and 'available_tags' in g.calls[0][2])

# A state file that will not read changes nothing.
bad = os.path.join(TMP, 'bad.json')
open(bad, 'w').write('{not json')
g, *_ = server()
said = run(bot.channel_setup(g, apply=True, path=bad))
yes('a state file that will not read changes nothing', g.calls == []
    and 'cannot be read' in said[0])

# No #test-tasks at all.
g = Guild()
said = run(bot.channel_setup(g, apply=True, path=os.path.join(TMP, 'none.json')))
yes('a server with no #test-tasks is told so and nothing is made',
    g.calls == [] and 'there is no #test-tasks' in said[0]
    and not os.path.exists(os.path.join(TMP, 'none.json')))


# --------------------------------------------------- 3. test tasks --
g, tasks, results, play, staff = server()
run(bot.channel_setup(g, apply=True, path=os.path.join(TMP, 'tasks.json')))
forum = bot._channel_named(g, 'test-tasks', ('forum',))
th, said = run(bot.post_test_task(g, 'Ride the ferry to Solstheim',
                                  'Board at Windhelm and arrive.', 'Dev'))
yes('a test task is one thread in the forum, titled and with its body',
    th is not None and len(forum.threads) == 1
    and forum.threads[0].name == 'Ride the ferry to Solstheim'
    and forum.threads[0].content == 'Board at Windhelm and arrive.')
yes('  tagged Dev', [t.name for t in th.applied_tags] == ['Dev'])
th2, said = run(bot.post_test_task(g, 'Buy a house', 'In Whiterun.', 'main'))
yes('a Main task gets the Main tag (any case)',
    [t.name for t in th2.applied_tags] == ['Main'])
again, said = run(bot.post_test_task(g, 'Ride the ferry to Solstheim', 'x', 'Dev'))
yes('the same title again is not a second thread',
    again is th and len(forum.threads) == 2 and said.startswith('Already'))
no, said = run(bot.post_test_task(g, 'x', 'y', 'Live'))
yes('a tag that is not Dev or Main is refused', no is None and 'Dev or Main' in said)
no, said = run(bot.post_test_task(g, 'x' * 101, 'y', 'Dev'))
yes('a title Discord would refuse is refused first', no is None)
g2, *_ = server()
no, said = run(bot.post_test_task(g2, 'x', 'y', 'Dev'))
yes('before the setup, it says #test-tasks is not a forum yet',
    no is None and 'not a forum yet' in said)


# --------------------------------------------------- 4. known issues --
class Msg(object):
    def __init__(self, ch, mid, content, author):
        self.channel = ch
        self.id = mid
        self.content = content
        self.author = author

    async def edit(self, content=None, **k):
        self.channel.edits.append((self.id, content))
        self.content = content


class Known(object):
    def __init__(self, me):
        self.id = 777
        self.me = me
        self.messages = {}
        self.edits = []
        self.next = 100

    async def send(self, content, **k):
        self.next += 1
        m = Msg(self, self.next, content, self.me)
        self.messages[m.id] = m
        return m

    async def fetch_message(self, mid):
        return self.messages[mid]

    async def history(self, limit=100):
        for mid in sorted(self.messages, reverse=True)[:limit]:
            yield self.messages[mid]


ISSUES = {}


def issue(num, title, label, state='open', reason=None, pr=False):
    row = {'number': num, 'title': title, 'state': state,
           'state_reason': reason,
           'html_url': 'https://github.com/EvilPatrick06/Thornswood/issues/%d' % num,
           'labels': [{'name': l} for l in label]}
    if pr:
        row['pull_request'] = {}
    ISSUES[num] = row


ASKED = []


def gh(url):
    ASKED.append(url)
    if '/issues/' in url and '?' not in url:
        return ISSUES[int(url.rsplit('/', 1)[1])]
    label = bot.urllib.parse.unquote(url.split('labels=')[1])
    return [r for r in ISSUES.values() if r['state'] == 'open'
            and label in [l['name'] for l in r['labels']]]


me = Target('Thornswood Bot', 2)
ch = Known(me)
issue(10, 'Ferry sinks', ['Dev Findings'])
issue(11, 'Gold resets', ['Main Findings', 'Dev Findings'])
issue(12, 'A PR', ['Dev Findings'], pr=True)
issue(13, 'Unlabelled', ['bug'])
st = {}
saves = []
posted, edited = run(bot.known_issues_once(ch, st, gh,
                                           save=lambda s: saves.append(len(s['issues']))))
yes('one post per open labelled issue, never for a pull request or an '
    'unlabelled issue, and one only for an issue with both labels',
    posted == [10, 11] and len(ch.messages) == 2)
yes('  each linking its issue',
    all('/issues/%d' % n in ch.messages[st['issues'][str(n)]['message_id']].content
        for n in (10, 11)))
yes('  saved straight after each post, not at the end', saves == [1, 2])
yes('  GitHub was asked with one query per label (labels are ANDed there)',
    len([u for u in ASKED if 'labels=' in u]) == 2)

posted, edited = run(bot.known_issues_once(ch, st, gh))
yes('a second pass posts nothing', posted == [] and len(ch.messages) == 2)

path = os.path.join(TMP, 'known-issues.json')
bot._known_save(dict(st, _dirty=True), path)
st2 = bot._state_read(path)
posted, _ = run(bot.known_issues_once(ch, st2, gh))
yes('after a restart, read back from known-issues.json, nothing is posted '
    'again', posted == [] and len(ch.messages) == 2)

# A crash between the post and its save: the file has 10 only.
st3 = {'issues': {'10': st['issues']['10']}}
run(bot.known_issues_recover(ch, st3, me.id))
posted, _ = run(bot.known_issues_once(ch, st3, gh))
yes('a post that never reached the file is found again in the channel and '
    'not doubled', posted == [] and len(ch.messages) == 2
    and st3['issues']['11']['message_id'] == st['issues']['11']['message_id'])

issue(10, 'Ferry sinks', ['Dev Findings'], state='closed', reason='completed')
issue(11, 'Gold resets', ['Main Findings'], state='closed', reason='not_planned')
posted, edited = run(bot.known_issues_once(ch, st, gh))
m10 = ch.messages[st['issues']['10']['message_id']].content
m11 = ch.messages[st['issues']['11']['message_id']].content
yes('closed as completed: the post is struck through and says Fixed',
    10 in edited and m10.startswith('~~') and '**Fixed**' in m10
    and st['issues']['10']['closed'] == 'completed')
yes('closed as not planned: it says Closed, not fixed',
    '**Closed, not fixed**' in m11 and st['issues']['11']['closed'] == 'not_planned')
n = len(ch.edits)
posted, edited = run(bot.known_issues_once(ch, st, gh))
yes('a closed post is not edited again on the next pass',
    edited == [] and len(ch.edits) == n and posted == [])

issue(10, 'Ferry sinks', ['Dev Findings'])
posted, edited = run(bot.known_issues_once(ch, st, gh))
yes('reopened on GitHub: the same post goes back to open, no new post',
    edited == [10] and posted == [] and len(ch.messages) == 2
    and '**Fixed**' not in ch.messages[st['issues']['10']['message_id']].content)

st4 = {}
run(bot.known_issues_recover(ch, st4, me.id))
yes('recovery reads a Fixed or Closed post back as closed',
    st4['issues']['11']['closed'] == 'not_planned'
    and st4['issues']['10']['closed'] is None)

saved_token = os.environ.pop('GITHUB_TOKEN', None)


class Ready(object):
    async def wait_until_ready(self):
        return None


real = bot.client
bot.client = Ready()
del LOGGED[:]
run(bot.watch_known_issues())
bot.client = real
yes('with no GITHUB_TOKEN the watcher says so once and stops',
    any('no GITHUB_TOKEN' in l for l in LOGGED))
yes('the poll is no more often than once a minute (default %ds)' % bot.KNOWN_EVERY,
    bot.KNOWN_EVERY >= 60)

shutil.rmtree(TMP, ignore_errors=True)
print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
