"""
test-moderation.py

The staff action watcher in bot.py (#412): what a moderator does in the game
(/kick, /freeze, /silence, /warn and the rest) is said in the staff channel,
once, from private\\moderation.log beside each game server.

Checked: what is already in the files when the bot starts is treated as said;
a new line is said once and says which server; a line still being written is
left for the next look; a line that is not an action says nothing; a flood is
one line; a file that cannot be read is skipped rather than read as empty;
nothing typed in the game can ping anybody.

The real bot module is imported and the real coroutine is run over real
files in a temp folder. Only the Discord send, the client and the sleep are
replaced. Read only. Never connects to anything.
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

import bot  # noqa: E402

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


class Stop(BaseException):
    """Ends the loop. BaseException, because the loop catches Exception."""


class AsyncioShim(object):
    def __init__(self, on_sleep):
        self._on_sleep = on_sleep

    def __getattr__(self, name):
        return getattr(asyncio, name)

    async def sleep(self, seconds):
        return self._on_sleep(seconds)


class FakeClient(object):
    guilds = []

    async def wait_until_ready(self):
        return None

    def is_closed(self):
        return False


WORK = tempfile.mkdtemp(prefix='thornswood-moderation-')
LIVE = os.path.join(WORK, 'live', 'moderation.log')
DEV = os.path.join(WORK, 'dev', 'moderation.log')
os.makedirs(os.path.dirname(LIVE))
os.makedirs(os.path.dirname(DEV))


def row(did, who='Bjorn', why='', n=0, **more):
    r = {'at': '2026-09-28T20:00:%02dZ' % n, 'server': 'main', 'did': did,
         'by': 1001, 'byName': 'Aela', 'who': 2002, 'whoName': who, 'why': why}
    r.update(more)
    return json.dumps(r)


def put(path, lines, tail=''):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(''.join(l + '\n' for l in lines) + tail)


def drive(steps):
    """Run watch_moderation; before each sleep, apply the next step (a
    function). Returns what was said before each sleep."""
    said = []
    ticks = []
    state = {'i': 0}

    async def fake_say(text):
        said.append(text)

    def on_sleep(seconds):
        ticks.append(list(said))
        del said[:]
        if state['i'] >= len(steps):
            raise Stop()
        steps[state['i']]()
        state['i'] += 1

    keep = (bot.MODERATION_LOGS, bot.report_say, bot.client, bot.asyncio)
    bot.MODERATION_LOGS = [('live', LIVE), ('dev', DEV)]
    bot.report_say = fake_say
    bot.client = FakeClient()
    bot.asyncio = AsyncioShim(on_sleep)
    try:
        try:
            asyncio.run(bot.watch_moderation())
        except Stop:
            pass
    finally:
        (bot.MODERATION_LOGS, bot.report_say, bot.client, bot.asyncio) = keep
    return ticks


try:
    yes('bot.py has the watcher', all(hasattr(bot, n) for n in
        ('watch_moderation', 'moderation_text', 'MODERATION_LOGS', 'MODERATION_EVERY')))

    # M1: what is there at start is said already.
    old = [row('warn', why='old', n=1)]
    put(LIVE, old)
    if os.path.exists(DEV):
        os.remove(DEV)
    ticks = drive([lambda: None])
    yes('M1 nothing already in the file is said on start', all(t == [] for t in ticks))

    # M2: a new line is said once, with the server it came from.
    put(LIVE, old)
    ticks = drive([lambda: put(LIVE, old + [row('kick', why='spam', n=2)]),
                   lambda: None, lambda: None])
    said = [s for t in ticks for s in t]
    yes('M2 a new kick is said', len(said) == 1 and 'removed Bjorn (profile 2002) from the world: spam' in said[0])
    yes('M2 and says the live server', len(said) == 1 and said[0].startswith('**Staff on the live server:**'))

    # M3: the dev server's file, from no file at all.
    put(LIVE, old)
    if os.path.exists(DEV):
        os.remove(DEV)
    ticks = drive([lambda: put(DEV, [row('freeze', n=3)]), lambda: None])
    said = [s for t in ticks for s in t]
    yes('M3 the dev file appearing is read, and says dev',
        len(said) == 1 and said[0].startswith('**Staff on the dev server:**') and 'froze Bjorn' in said[0])

    # M4: a line still being written waits for its line ending.
    put(LIVE, old)
    put(DEV, [])
    half = row('warn', why='mid write', n=4)
    ticks = drive([lambda: put(LIVE, old, half[:20]),
                   lambda: put(LIVE, old + [half]), lambda: None])
    yes('M4 half a line says nothing', ticks[1] == [])
    yes('M4 and the whole line is said once it lands', len(ticks[2]) == 1 and 'mid write' in ticks[2][0])

    # M5: rubbish is skipped, the loop carries on.
    put(LIVE, old)
    ticks = drive([lambda: put(LIVE, old + ['not json', row('nonsense', n=5), row('warn', why='real', n=6)]),
                   lambda: None])
    said = [s for t in ticks for s in t]
    yes('M5 only the real action is said', len(said) == 1 and 'real' in said[0])

    # M6: a flood is one line.
    put(LIVE, old)
    many = [row('silence', n=10 + i, minutes=5) for i in range(12)]
    ticks = drive([lambda: put(LIVE, old + many), lambda: None])
    said = [s for t in ticks for s in t]
    yes('M6 twelve at once is one line saying how many', len(said) == 1 and '12 staff actions' in said[0])

    # M7: nothing typed in the game pings anybody.
    text = bot.moderation_text('live', json.loads(row('warn', who='@everyone', why='<@&111111111111111111> [x](http://e.invalid)')))
    yes('M7 an @everyone in a name is text', '@everyone' not in text and '@\u200beveryone' in text)
    yes('M7 a role mention in a reason is text', '<@&111111111111111111>' not in text)
    yes('M7 a masked link is shown as what it is', '\\[x](http://e.invalid)' in text)
    for w in (text, bot.moderation_text('dev', json.loads(row('kick')))):
        if 'player' in w.lower() or '\u2014' in w:
            yes('M7 the words are the house words', False)
            break
    else:
        yes('M7 the words are the house words', True)

    # M8: every action the gamemode writes has words here.
    gm = open(os.path.join(HERE, '..', 'game', 'gamemode.js'), encoding='utf-8').read()
    dids = ['kick', 'freeze', 'unfreeze', 'bring', 'goto', 'silence', 'unsilence', 'warn',
            'give', 'spawn', 'tp', 'ban', 'unban', 'note',
            # One character or the whole account, and PK (#1010).
            'banaccount', 'unbanaccount', 'pk']
    yes('M8 every action the staff block records has a sentence here',
        all(("record('%s'" % d) in gm and d in bot._MOD_DID for d in dids))
    site = open(os.path.join(HERE, '..', 'site', 'server.js'), encoding='utf-8').read()
    yes('M8 and so does every one the hub writes',
        all(("modLog({ did: '%s'" % d) in site and d in bot._MOD_DID
            for d in ('ban', 'unban', 'note', 'banaccount', 'unbanaccount', 'pk')))

    # M10: the hub's lines say the site, and name a person by account.
    hub = bot.moderation_text('site', {'did': 'banaccount', 'byName': 'Aela', 'whoName': 'Bjorn',
                                       'why': 'until 2026-10-01 18:00 UTC: spam'})
    yes('M10 an account ban from the hub says the site and the whole account, with no profile number',
        hub == '**Staff on the site:** Aela banned the whole account of Bjorn, every character on it: '
               'until 2026-10-01 18:00 UTC: spam')
    game = bot.moderation_text('live', json.loads(row('ban', why='for good: cheating')))
    yes('M10 a character ban from the game says the server, the character and the profiles',
        game == '**Staff on the live server:** Aela (profile 1001) banned the character Bjorn (profile 2002): '
                'for good: cheating')
    pk = bot.moderation_text('dev', json.loads(row('pk', why='died in the siege')))
    yes('M10 a PK says the character died for good, and why',
        pk == '**Staff on the dev server:** Aela (profile 1001) killed Bjorn (profile 2002) for good (PK), '
              'quietly: died in the siege')
    note = bot.moderation_text('dev', json.loads(row('note', why='asked twice about the bridge')))
    yes('M10 a note says what it says', 'wrote a note on Bjorn (profile 2002): asked twice' in note)

    # M11: somebody's own /stuck (#414) says the server, the person and the
    # gamemode's whole sentence, not "Staff on", and pings nobody.
    stuck = bot.moderation_text('dev', {
        'did': 'stuck', 'by': 2002, 'byName': 'Bjorn', 'who': 2002, 'whoName': 'Bjorn',
        'why': 'used /stuck and was sent back a few steps, from 3c:Skyrim.esm (1, 2, 3) to '
               '3c:Skyrim.esm (400, 2, 3). Character ff000002, Discord 111.'})
    yes('M11 a /stuck line says the server, the person and where from and to',
        stuck == '**/stuck on the dev server:** Bjorn (profile 2002) used /stuck and was sent back '
                 'a few steps, from 3c:Skyrim.esm (1, 2, 3) to 3c:Skyrim.esm (400, 2, 3). '
                 'Character ff000002, Discord 111.')
    yes('M11 the gamemode writes it', "did: 'stuck'" in gm and 'stuck' in bot._MOD_DID)
    pinged = bot.moderation_text('live', {'did': 'stuck', 'by': 5, 'byName': '@everyone',
                                          'why': 'used /stuck <@&111111111111111111>'})
    yes('M11 nothing in it pings anybody', '@everyone' not in pinged and '<@&111111111111111111>' not in pinged)

    # M9: started with the others, and sent through report_say (mentions off).
    src = inspect.getsource(bot.on_ready)
    yes('M9 on_ready starts it', 'asyncio.create_task(watch_moderation())' in src)
    yes('M9 it speaks through report_say', 'report_say(' in inspect.getsource(bot.watch_moderation))
    logs = dict(bot.MODERATION_LOGS)
    yes('M9 by default it reads both game servers\' private folders and the site\'s data folder',
        [w for w, _ in bot.MODERATION_LOGS] == ['live', 'dev', 'site']
        and logs['live'].endswith(os.path.join('private', 'moderation.log'))
        and logs['dev'].endswith(os.path.join('private', 'moderation.log'))
        and os.path.dirname(logs['site']) == os.path.dirname(bot.TROUBLE_FILE))
finally:
    shutil.rmtree(WORK, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
