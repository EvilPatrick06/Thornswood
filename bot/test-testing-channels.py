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
     closed or unlabelled, its post is deleted; reopened, it is back.
  5. Test tasks from the board: one post per issue closed as fixed, always
     tagged Main whatever "Server:" line its "Test task:" comment carries
     (Patrick, 11 Oct: an issue closes when its fix is on main, where testers
     test), the Server line never in the body, the plain bodies saying main.
  6. Posts made with an older form (TASK_FORM, KNOWN_FORM) are written again
     once after the bot is updated, though GitHub says nothing changed, and
     after that an unchanged issue is not read again.

The real bot module is imported. Discord and GitHub are stand-ins that
count what is asked of them. Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.10 or newer, #2276)
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
    def __init__(self, name, tags, content, forum=None, owner=2):
        self.name = name
        self.applied_tags = tags
        self.content = content
        self.archived = False
        self.mention = '<#%s>' % name
        self.forum = forum
        self.owner_id = owner
        Thread.next = getattr(Thread, 'next', 50000) + 1
        self.id = Thread.next
        if forum is not None:
            forum.guild.threads[self.id] = self

    async def edit(self, name=None, applied_tags=None, **k):
        self.forum.guild.calls.append(('edit_thread', self.forum.name, name))
        if name is not None:
            self.name = name
        if applied_tags is not None:
            self.applied_tags = applied_tags

    @property
    def starter_message(self):
        th = self

        class Starter(object):
            async def edit(self, content=None, **k):
                th.content = content
        return Starter()

    async def delete(self):
        self.forum.guild.calls.append(('delete_thread', self.forum.name, self.name))
        self.forum.threads.remove(self)
        del self.forum.guild.threads[self.id]


class Said(object):
    def __init__(self, author, content='x'):
        self.author = author
        self.content = content


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
        self.said = []
        guild.channels.append(self)

    async def history(self, limit=100):
        for m in self.said[:limit]:
            yield m

    async def delete(self, reason=None):
        self.guild.calls.append(('delete', self.name))
        self.guild.channels.remove(self)

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

    async def create_thread(self, name, content, applied_tags, reason=None, **k):
        self.guild.calls.append(('create_thread', self.name, name))
        th = Thread(name, applied_tags, content, self)
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
        self.threads = {}

    def get_thread(self, tid):
        return self.threads.get(tid)

    async def fetch_channel(self, tid):
        if tid in self.threads:
            return self.threads[tid]
        raise discord.NotFound(type('R', (), {'status': 404, 'reason': 'gone'})(), 'Unknown Channel')

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
    and 'would make the forum #known-issues in Testing' in text
    and 'would make #known-issues read only' in text)

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
known = bot._channel_named(g, 'known-issues', ('forum',))
yes('#known-issues is made as a FORUM, with the Dev and Main tags',
    known is not None and bot._channel_named(g, 'known-issues', ('text',)) is None
    and sorted(x.name for x in known.available_tags) == ['Dev', 'Main'])
yes('#known-issues is made beside #test-findings, seen by the same people',
    known is not None and known.category is results.category
    and set(results.overwrites) <= set(known.overwrites)
    and all(known.overwrites[t].view_channel == results.overwrites[t].view_channel
            for t in results.overwrites))
yes('  and read only: no sending or threads for @everyone or the copied '
    'tester overwrite',
    all(known.overwrites[t].send_messages is False
        and known.overwrites[t].send_messages_in_threads is False
        and known.overwrites[t].create_public_threads is False
        for t in (g.default_role, play)))
yes('  while the bot keeps posting there, and may delete its posts',
    known.overwrites[g.me].send_messages is True
    and known.overwrites[g.me].view_channel is True
    and known.overwrites[g.me].manage_threads is True)
yes('  and #test-findings itself is untouched by that',
    results.overwrites[play].send_messages is True)
done = json.load(open(state))
yes('the apply is recorded in the state file by server id, the forum step too',
    '1' in done.get('guilds', {}) and done['guilds']['1'].get('done')
    and done['guilds']['1'].get('known_forum'))

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
    and not [c for c in g.calls if c[0] == 'create_forum' and c[1] == 'test-tasks']
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
    [c[0] for c in g.calls] == ['edit', 'create_forum']
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


# ----------------------------------- 2b. #known-issues becomes a forum --
# A server set up on 11 Oct before this: a text #known-issues full of the
# bot's own list, and a state file with done but no known_forum.
def old_shape(state_path, with_human=False):
    g, tasks, results, play, staff = server()
    run(bot.channel_setup(g, apply=True, path=state_path))
    forum_k = bot._channel_named(g, 'known-issues', ('forum',))
    g.channels.remove(forum_k)
    k = Channel(g, 'known-issues', 'text', results.category, 5,
                bot.known_overwrites(g, results))
    k.said = [Said(g.me) for _ in range(26)]
    if with_human:
        k.said.append(Said(play, 'a person wrote here'))
    st = json.load(open(state_path))
    st['guilds']['1'].pop('known_forum', None)
    json.dump(st, open(state_path, 'w'))
    tasks_forum = bot._channel_named(g, 'test-tasks', ('forum',))
    tasks_forum.overwrites[g.me] = OW(view_channel=True, send_messages=True)
    g.calls = []
    return g, k, tasks_forum


mig = os.path.join(TMP, 'migrate.json')
g, k, tf = old_shape(mig)
said = run(bot.channel_setup(g, apply=False, path=mig))
text = '\n'.join(said)
yes('on a server set up before, a preview says it would delete the text '
    '#known-issues (only the bot\'s own list) and make the forum, and asks '
    'Discord for nothing',
    g.calls == [] and 'would delete the text #known-issues' in text
    and 'its 26 message(s) are all the bot' in text
    and 'would make the forum #known-issues' in text)
said = run(bot.channel_setup(g, apply=True, path=mig))
kf = bot._channel_named(g, 'known-issues', ('forum',))
yes('  the apply deletes that text channel and makes the forum in its place',
    ('delete', 'known-issues') in g.calls and k not in g.channels
    and kf is not None and kf.category is k.category)
yes('  the bot may now delete posts in #test-tasks too (for a reopened issue)',
    tf.overwrites[g.me].manage_threads is True)
yes('  recorded as known_forum, and a second run does nothing',
    json.load(open(mig))['guilds']['1'].get('known_forum')
    and (lambda c: (run(bot.channel_setup(g, apply=True, path=mig)), g.calls == c)[1])(list(g.calls)))

mig2 = os.path.join(TMP, 'migrate2.json')
g, k, tf = old_shape(mig2, with_human=True)
run(bot.channel_setup(g, apply=True, path=mig2))
yes('a text #known-issues holding anything that is not the bot\'s is kept, '
    'renamed known-issues-archive and locked, never deleted',
    k in g.channels and k.name == 'known-issues-archive'
    and not [c for c in g.calls if c[0] == 'delete']
    and bot._channel_named(g, 'known-issues', ('forum',)) is not None)


# --------------------------------------------------- 3. test tasks --
g, tasks, results, play, staff = server()
run(bot.channel_setup(g, apply=True, path=os.path.join(TMP, 'tasks.json')))
forum = bot._channel_named(g, 'test-tasks', ('forum',))
th, said = run(bot.post_test_task(g, 'Ride the ferry to Solstheim',
                                  'Board at Windhelm and arrive.'))
yes('a test task is one thread in the forum, titled and with its body',
    th is not None and len(forum.threads) == 1
    and forum.threads[0].name == 'Ride the ferry to Solstheim'
    and forum.threads[0].content == 'Board at Windhelm and arrive.')
yes('  tagged Main by default (#2276: Main only)',
    [t.name for t in th.applied_tags] == ['Main'])
th2, said = run(bot.post_test_task(g, 'Buy a house', 'In Whiterun.', 'main'))
yes('a Main task gets the Main tag (any case)',
    [t.name for t in th2.applied_tags] == ['Main'])
no, said = run(bot.post_test_task(g, 'Fish in Riften', 'At the docks.', 'Dev'))
yes('#2276: a hand post tagged Dev is refused, nothing is posted',
    no is None and 'Main only' in said and len(forum.threads) == 2
    and not [x for x in forum.threads if x.name == 'Fish in Riften'])
again, said = run(bot.post_test_task(g, 'Ride the ferry to Solstheim', 'x'))
yes('the same title again is not a second thread',
    again is th and len(forum.threads) == 2 and said.startswith('Already'))
no, said = run(bot.post_test_task(g, 'x', 'y', 'Live'))
yes('a tag that is not Main is refused', no is None and 'Main only' in said)
no, said = run(bot.post_test_task(g, 'x' * 101, 'y'))
yes('a title Discord would refuse is refused first', no is None)
g2, *_ = server()
no, said = run(bot.post_test_task(g2, 'x', 'y'))
yes('before the setup, it says #test-tasks is not a forum yet',
    no is None and 'not a forum yet' in said)
import inspect as _insp  # noqa: E402
_params = list(_insp.signature(bot.test_task_cmd.callback).parameters)
yes('#2276: /test-task has no tag option, so it cannot post to Dev (%s)'
    % _params, 'tag' not in _params)
_src = _insp.getsource(bot)
yes('#2276: --post-task --tag takes Main only, Main by default',
    "ap.add_argument('--tag', choices=[TASK_POST_TAG], default=TASK_POST_TAG)" in _src
    and bot.TASK_POST_TAG == 'Main')


# --------------------------------------------------- 4. known issues --
ISSUES = {}
COMMENTS = {}


UPD = [0]


def issue(num, title, label, state='open', reason=None, pr=False,
          closed_at=None):
    UPD[0] += 1
    row = {'number': num, 'title': title, 'state': state,
           'state_reason': reason, 'closed_at': closed_at,
           'updated_at': '2026-10-12T06:%02d:%02dZ' % divmod(UPD[0], 60),
           'html_url': 'https://github.com/EvilPatrick06/Thornswood/issues/%d' % num,
           'labels': [{'name': l} for l in label]}
    if pr:
        row['pull_request'] = {}
    ISSUES[num] = row


ASKED = []


def gh(url):
    ASKED.append(url)
    path = url.split('?')[0]
    if path.endswith('/comments'):
        return COMMENTS.get(int(path.split('/')[-2]), [])
    if '/issues/' in path:
        return ISSUES[int(path.rsplit('/', 1)[1])]
    if 'state=closed' in url:
        since = bot.urllib.parse.unquote(url.split('since=')[1].split('&')[0])
        return [r for r in ISSUES.values() if r['state'] == 'closed'
                and r['updated_at'] >= since]
    label = bot.urllib.parse.unquote(url.split('labels=')[1])
    return [r for r in ISSUES.values() if r['state'] == 'open'
            and label in [l['name'] for l in r['labels']]]


g, tasks, results, play, staff = server()
run(bot.channel_setup(g, apply=True, path=os.path.join(TMP, 'known.json')))
kf = bot._channel_named(g, 'known-issues', ('forum',))
tf = bot._channel_named(g, 'test-tasks', ('forum',))
me = g.me
issue(10, 'Ferry sinks', ['Dev Findings'])
issue(11, 'Gold resets', ['Main Findings', 'Dev Findings'])
issue(12, 'A PR', ['Dev Findings'], pr=True)
issue(13, 'Unlabelled', ['bug'])
st = {'issues': {'99': {'message_id': 5, 'channel_id': 1234, 'closed': None}}}
saves = []
posted, edited, removed = run(bot.known_issues_once(kf, st, gh,
                      save=lambda s: saves.append(len(s['issues'])), me_id=me.id))
yes('one forum POST per open labelled issue, never for a pull request or an '
    'unlabelled issue, one only for an issue with both labels',
    posted == [10, 11] and len(kf.threads) == 2)
yes('  each titled with the issue\'s title, tagged Dev or Main by its label',
    [(th.name, sorted(x.name for x in th.applied_tags)) for th in kf.threads]
    == [('Ferry sinks', ['Dev']), ('Gold resets', ['Dev', 'Main'])])
yes('  with no issue number and no link in the post',
    not any('#1' in th.content or 'http' in th.content for th in kf.threads))
yes('  saved straight after each post', saves == [1, 2])
yes('  and a record from the old text channel is forgotten, not acted on',
    '99' not in st['issues'] and removed == [])
posted, edited, removed = run(bot.known_issues_once(kf, st, gh, me_id=me.id))
yes('a second pass posts and removes nothing', posted == [] and removed == []
    and len(kf.threads) == 2)
path = os.path.join(TMP, 'known-issues.json')
bot._known_save(dict(st, _dirty=True), path)
posted, _, _ = run(bot.known_issues_once(kf, bot._state_read(path), gh, me_id=me.id))
yes('after a restart, read back from the file, nothing is posted again',
    posted == [] and len(kf.threads) == 2)
st3 = {'issues': {'10': st['issues']['10']}}
posted, _, _ = run(bot.known_issues_once(kf, st3, gh, me_id=me.id))
yes('a post that never reached the file is found again by its title, not doubled',
    posted == [11] and len(kf.threads) == 2
    and st3['issues']['11']['thread_id'] == st['issues']['11']['thread_id'])

issue(10, 'Ferry sinks', ['Dev Findings'], state='closed', reason='completed',
      closed_at='2026-10-12T05:00:00Z')
issue(11, 'Gold resets', ['bug'])
posted, edited, removed = run(bot.known_issues_once(kf, st, gh, me_id=me.id))
yes('fixed and closed, or the findings label taken off: the post is DELETED',
    sorted(removed) == [10, 11] and kf.threads == []
    and [c for c in g.calls if c[0] == 'delete_thread'])
issue(10, 'Ferry sinks', ['Dev Findings'])
posted, edited, removed = run(bot.known_issues_once(kf, st, gh, me_id=me.id))
yes('reopened as a finding: a post again', posted == [10] and len(kf.threads) == 1)


# --------------------------------------------- 5. automatic test tasks --
ISSUES.clear()
tst = {}
issue(30, 'Old fix', ['Dev Findings'], state='closed', reason='completed',
      closed_at='2026-10-01T00:00:00Z')
posted, edited, removed = run(bot.test_tasks_once(tf, tst, gh, me_id=me.id,
                                         now='2026-10-12T04:00:00Z'))
yes('the first pass only sets the start: nothing closed before it is posted',
    posted == [] and tst['since'] == '2026-10-12T04:00:00Z' and tf.threads == [])
issue(31, 'Ferry sinks', ['Dev Findings'], state='closed', reason='completed',
      closed_at='2026-10-12T05:00:00Z')
COMMENTS[31] = [{'body': 'Fixed in the gamemode.'},
                {'body': 'Test task: Ride the ferry to Solstheim\nServer: Dev\n'
                         'Board at Windhelm and ride across.\nYou arrive dry.'}]
issue(32, 'Gold resets', ['Dev Findings'], state='closed', reason='completed',
      closed_at='2026-10-12T05:01:00Z')
issue(33, 'Tooling only', ['area: Release'], state='closed', reason='completed',
      closed_at='2026-10-12T05:02:00Z')
issue(34, 'Will not do', ['Dev Findings'], state='closed', reason='not_planned',
      closed_at='2026-10-12T05:03:00Z')
issue(35, 'Launcher fix', ['area: Launcher'], state='closed', reason='completed',
      closed_at='2026-10-12T05:04:00Z')
COMMENTS[35] = [{'body': 'test task: Open the server list\nIt opens on your server.'}]
posted, edited, removed = run(bot.test_tasks_once(tf, tst, gh, me_id=me.id))
by = dict((th.name, th) for th in tf.threads)
yes('a fixed issue becomes a test task post, titled and written from its '
    '"Test task:" comment, tagged Main even though its Server line says Dev, '
    'and the Server line is not in the body',
    'Ride the ferry to Solstheim' in by
    and by['Ride the ferry to Solstheim'].content
    == 'Board at Windhelm and ride across.\nYou arrive dry.'
    and [x.name for x in by['Ride the ferry to Solstheim'].applied_tags] == ['Main'])
yes('  a fixed finding with no such comment gets its own title and a plain line '
    'that says to check it on main, tagged Main though it was found on Dev',
    'Gold resets' in by and by['Gold resets'].content.startswith('This was fixed')
    and 'Check it on main' in by['Gold resets'].content
    and [x.name for x in by['Gold resets'].applied_tags] == ['Main'])
yes('  any fixed issue with a "Test task:" comment is posted, finding or not, '
    'tagged Main with no Server line at all',
    'Open the server list' in by
    and [x.name for x in by['Open the server list'].applied_tags] == ['Main'])
yes('  every test task the bot posted carries the one tag Main',
    all([x.name for x in th.applied_tags] == ['Main'] for th in tf.threads))
yes('  but not a fixed issue with neither, and not one closed as not planned',
    'Tooling only' not in by and 'Will not do' not in by
    and sorted(posted) == [31, 32, 35])
posted, edited, removed = run(bot.test_tasks_once(tf, tst, gh, me_id=me.id))
yes('a second pass posts nothing twice', posted == [] and len(tf.threads) == 3)
issue(32, 'Gold resets', ['Main Findings'])
posted, edited, removed = run(bot.test_tasks_once(tf, tst, gh, me_id=me.id))
yes('a reopened issue loses its test task post',
    removed == [32] and 'Gold resets' not in [th.name for th in tf.threads])


# ----------------------------- 6. written for testers, and kept up to date --
ISSUES.clear()
COMMENTS.clear()
g, tasks, results, play, staff = server()
run(bot.channel_setup(g, apply=True, path=os.path.join(TMP, 'written.json')))
kf = bot._channel_named(g, 'known-issues', ('forum',))
tf = bot._channel_named(g, 'test-tasks', ('forum',))
issue(40, 'Smith', ['Main Findings'])
COMMENTS[40] = [{'body': 'Known issue: Forge tells you to wait for ever\n'
                         'At a forge the bar fills and never finishes.\nLeave and come back.',
                 'created_at': '2026-10-12T06:00:00Z'}]
issue(41, 'Bare title', ['Dev Findings'])
st = {}
posted, edited, removed = run(bot.known_issues_once(kf, st, gh, me_id=me.id))
by = dict((th.name, th) for th in kf.threads)
yes('a "Known issue:" comment gives the post its short title and its body, '
    'tagged by the label',
    'Forge tells you to wait for ever' in by
    and by['Forge tells you to wait for ever'].content
    == 'At a forge the bar fills and never finishes.\nLeave and come back.'
    and [x.name for x in by['Forge tells you to wait for ever'].applied_tags] == ['Main'])
yes('  an issue with none still gets a post, from its own title, until one is written',
    'Bare title' in by)
before = len([u for u in ASKED if u.endswith('/comments') or '/comments?' in u])
posted, edited, removed = run(bot.known_issues_once(kf, st, gh, me_id=me.id))
after = len([u for u in ASKED if u.endswith('/comments') or '/comments?' in u])
yes('an issue GitHub says did not change is not read again (no comment calls)',
    after == before and posted == edited == removed == [])
COMMENTS[41] = [{'body': 'Known issue: Doors stick shut in Riften\nServer: Dev\n'
                         'Some Riften doors will not open.', 'created_at': '2026-10-12T06:01:00Z'}]
issue(41, 'Bare title', ['Dev Findings'])
posted, edited, removed = run(bot.known_issues_once(kf, st, gh, me_id=me.id))
yes('a comment written later EDITS the same post: new title and body, no second post',
    edited == [41] and posted == [] and len(kf.threads) == 2
    and 'Doors stick shut in Riften' in [th.name for th in kf.threads]
    and 'Bare title' not in [th.name for th in kf.threads])

tst = {}
run(bot.test_tasks_once(tf, tst, gh, me_id=me.id, now='2026-10-12T05:00:00Z'))
issue(50, 'Old one', ['area: Launcher'], state='closed', reason='completed',
      closed_at='2026-10-11T20:00:00Z')
COMMENTS[50] = [{'body': 'Test task: Server list opens on yours\nOpen the launcher.',
                 'created_at': '2026-10-12T05:30:00Z'}]
issue(51, 'Ferry sinks at the dock', ['Dev Findings'], state='closed',
      reason='completed', closed_at='2026-10-12T05:10:00Z')
COMMENTS[51] = [{'body': 'Test task:\nServer: Dev\nRide the ferry.',
                 'created_at': '2026-10-12T05:11:00Z'}]
posted, edited, removed = run(bot.test_tasks_once(tf, tst, gh, me_id=me.id))
names = [th.name for th in tf.threads]
yes('a closed issue whose "Test task:" comment was written after the start gets '
    'a post, however long ago it closed',
    50 in posted and 'Server list opens on yours' in names)
yes('  and "Test task:" with nothing after it takes the issue\'s own title',
    51 in posted and 'Ferry sinks at the dock' in names)
th51 = [th for th in tf.threads if th.name == 'Ferry sinks at the dock']
yes('  its "Server: Dev" line is read and dropped: the body is only what '
    'follows it, and the tag is Main',
    len(th51) == 1 and th51[0].content == 'Ride the ferry.'
    and [x.name for x in th51[0].applied_tags] == ['Main'])
COMMENTS[51].append({'body': 'Test task: Ferry crossing works\nServer: Main\n'
                             '1. Board the ferry.\nWhat should happen: you arrive.',
                     'created_at': '2026-10-12T06:30:00Z'})
issue(51, 'Ferry sinks at the dock', ['Dev Findings'], state='closed',
      reason='completed', closed_at='2026-10-12T05:10:00Z')
posted, edited, removed = run(bot.test_tasks_once(tf, tst, gh, me_id=me.id))
th51 = [th for th in tf.threads if th.name == 'Ferry crossing works']
yes('a rewritten "Test task:" comment EDITS its post: title, body and tag',
    edited == [51] and posted == [] and len(th51) == 1
    and th51[0].content == '1. Board the ferry.\nWhat should happen: you arrive.'
    and [x.name for x in th51[0].applied_tags] == ['Main'])

# A post made by hand (--post-task) is adopted, then brought up to date.
made = run(tf.create_thread(name='Long hand title', content='old', applied_tags=[]))
kpath = os.path.join(TMP, 'adopt.json')
bot._state_write(kpath, dict(tst))
said = bot.adopt_task(60, made.id, path=kpath)
issue(60, 'Hand posted', ['Dev Findings'], state='closed', reason='completed',
      closed_at='2026-10-11T21:00:00Z')
COMMENTS[60] = [{'body': 'Test task: Short and clear\nDo the thing.',
                 'created_at': '2026-10-11T21:00:00Z'}]
st5 = bot._state_read(kpath)
posted, edited, removed = run(bot.test_tasks_once(tf, st5, gh, me_id=me.id))
yes('an adopted hand post belongs to its issue and is edited to its test task',
    'now owns test task post' in said and 60 in edited
    and made.name == 'Short and clear' and made.content == 'Do the thing.'
    and [x.name for x in made.applied_tags] == ['Main'])


# ------------------------------- 7. what the plain bodies say, under main --
nobody = {'title': 'Ferry', 'labels': [{'name': 'Dev Findings'}]}
yes('the plain test task body says the fix is on main and to check it there',
    'on main' in bot.default_task_body(nobody)
    and 'Check it on main' in bot.default_task_body(nobody)
    and 'dev' not in bot.default_task_body(nobody).lower())
yes('a "Test task:" comment with no body gets "Check this on main."',
    bot.test_task_of(nobody, [{'body': 'Test task: Ferry\nServer: Dev',
                               'created_at': 'x'}])
    == ('Ferry', 'Check this on main.', 'x'))
yes('the plain known issue body says it goes when the fix is on main, and '
    'still names where it was found',
    bot.known_body(nobody).startswith('Known on Dev.')
    and 'fix is on main' in bot.known_body(nobody))
yes('known issues keep their Dev and Main tags: by label, or by a "Server:" '
    'line under "Known issue:"',
    bot.known_of(nobody, [])[2] == ['Dev']
    and bot.known_of(nobody, [{'body': 'Known issue: X\nServer: Main\nY'}])[2]
    == ['Main'])


# ------------------------- 8. posts of an older form are written again --
# Records written by the bot before TASK_FORM and KNOWN_FORM: no form in
# them, posts tagged and worded the old way, and GitHub says nothing changed.
ISSUES.clear()
COMMENTS.clear()
g, tasks, results, play, staff = server()
run(bot.channel_setup(g, apply=True, path=os.path.join(TMP, 'form.json')))
kf = bot._channel_named(g, 'known-issues', ('forum',))
tf = bot._channel_named(g, 'test-tasks', ('forum',))


def tag(forum, name):
    return [bot.task_tag_of(forum, name)]


issue(70, 'Doors stick', ['Dev Findings'], state='closed', reason='completed',
      closed_at='2026-10-12T05:20:00Z')
COMMENTS[70] = [{'body': 'Test task: Riften doors open\nServer: Dev\nOpen a door.',
                 'created_at': '2026-10-12T05:21:00Z'}]
issue(71, 'Gold resets', ['Dev Findings'], state='closed', reason='completed',
      closed_at='2026-10-12T05:22:00Z')
issue(72, 'Old close', ['area: Launcher'], state='closed', reason='completed',
      closed_at='2026-10-11T20:00:00Z')
COMMENTS[72] = [{'body': 'Test task: List opens\nServer: Dev\nOpen it.',
                 'created_at': '2026-10-11T20:00:00Z'}]
ISSUES[72]['updated_at'] = '2026-10-11T20:00:00Z'   # untouched since the start
issue(73, 'Smith', ['Dev Findings'])
issue(74, 'Forge', ['Main Findings'])
COMMENTS[74] = [{'body': 'Known issue: Forge waits for ever\nIt never finishes.'}]
old_known = 'Known on Dev. The team is working on it; this post goes when it is fixed.'
th70 = run(tf.create_thread(name='Riften doors open', content='Open a door.',
                            applied_tags=tag(tf, 'Dev')))
th71 = run(tf.create_thread(name='Gold resets', applied_tags=tag(tf, 'Dev'),
                            content='This was fixed. Check it on Dev, and say in '
                                    '#test-findings if it still happens.'))
th72 = run(tf.create_thread(name='List opens', content='Open it.',
                            applied_tags=tag(tf, 'Dev')))
th73 = run(kf.create_thread(name='Smith', content=old_known,
                            applied_tags=tag(kf, 'Dev')))
th74 = run(kf.create_thread(name='Forge waits for ever', content='It never finishes.',
                            applied_tags=tag(kf, 'Main')))


def old(th, num, tags):
    return {'thread_id': th.id, 'channel_id': th.forum.id,
            'sig': bot._sig(th.name, th.content, tags),
            'updated': ISSUES[num]['updated_at']}


fst = {'since': '2026-10-12T05:00:00Z',
       'tasks': {'70': old(th70, 70, ['Dev']), '71': old(th71, 71, ['Dev']),
                 '72': old(th72, 72, ['Dev'])},
       'issues': {'73': old(th73, 73, ['Dev']), '74': old(th74, 74, ['Main'])}}
fpath = os.path.join(TMP, 'form-state.json')
bot._known_save(dict(fst, _dirty=True), fpath)
fst = bot._state_read(fpath)
posted, edited, removed = run(bot.test_tasks_once(tf, fst, gh, me_id=me.id))
yes('after the update, a test task posted tagged Dev is EDITED to Main on the '
    'next pass, though its issue did not change, and nothing is posted twice',
    sorted(edited) == [70, 71, 72] and posted == [] and removed == []
    and len(tf.threads) == 3
    and all([x.name for x in th.applied_tags] == ['Main'] for th in (th70, th71, th72)))
yes('  the plain body is rewritten to say main; a written body is kept as it was',
    'Check it on main' in th71.content and th70.content == 'Open a door.'
    and th72.content == 'Open it.')
yes('  including a post whose issue closed before the start (adopted)',
    72 in edited)
yes('  and every record now holds the new form',
    all(r.get('form') == bot.TASK_FORM for r in fst['tasks'].values()))
posted, edited, removed = run(bot.known_issues_once(kf, fst, gh, me_id=me.id))
yes('a known issue with the old plain line is EDITED to the new one, once, '
    'and keeps its Dev tag',
    edited == [73] and posted == [] and removed == [] and len(kf.threads) == 2
    and 'fix is on main' in th73.content
    and [x.name for x in th73.applied_tags] == ['Dev'])
yes('  a known issue with a written body is not edited, but its record takes '
    'the new form',
    th74.content == 'It never finishes.'
    and [x.name for x in th74.applied_tags] == ['Main']
    and all(r.get('form') == bot.KNOWN_FORM for r in fst['issues'].values()))
bot._known_save(dict(fst, _dirty=True), fpath)
fst = bot._state_read(fpath)
before = len([u for u in ASKED if '/comments' in u])
calls = len(g.calls)
t_out = run(bot.test_tasks_once(tf, fst, gh, me_id=me.id))
k_out = run(bot.known_issues_once(kf, fst, gh, me_id=me.id))
after = len([u for u in ASKED if '/comments' in u])
yes('once rewritten and read back after a restart, the next passes read no '
    'comments and change nothing: the rewrite happens once, not every pass',
    after == before and len(g.calls) == calls
    and t_out == ([], [], []) and k_out == ([], [], []))


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
