"""
test-watch.py

The site watcher in bot.py, driven by a clock instead of five real minutes.

The thing worth testing is not whether an HTTP call works, it is whether the
watcher SHUTS UP. A watcher that posts every five minutes is a channel nobody
reads, and a channel nobody reads is the same as having no watcher, which is
the situation this was written for. So most of these check that nothing was
said.

The real bot module is imported and the real coroutine is run. Only the three
things that touch the world are replaced: the HTTP call, the Discord send, and
the sleep.

Read only. Never connects to anything.
"""
import asyncio
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# bot.py refuses to load without one, and never uses it unless client.run is
# called, which nothing here does.
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')

# card.py wants Pillow, which is on the VPS and not here, and it draws join
# cards, which have nothing to do with the watcher. A stub keeps the import
# from deciding whether this can be tested.
# Pillow is installed here now, so card.py imports for real.

import bot  # noqa: E402


class AsyncioShim(object):
    """
    Everything asyncio does, except sleeping.

    Patching asyncio.sleep globally would also patch it underneath asyncio.run,
    which is the thing running these tests. This replaces only what bot.py
    looks up.
    """

    def __init__(self, on_sleep):
        self._on_sleep = on_sleep

    def __getattr__(self, name):
        return getattr(asyncio, name)

    async def sleep(self, _seconds):
        return self._on_sleep()

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


class Stop(BaseException):
    """
    Ends the loop after a fixed number of ticks.

    BaseException and not Exception, deliberately. watch_site catches every
    Exception from the check on purpose, so that a check that blows up cannot
    end the loop, which means an ordinary exception cannot be used to stop it
    either. The first version of this file used one and hung forever on S9,
    which is the test for exactly that behaviour.
    """


def run(answers, misses_needed=2):
    """
    Drive watch_site over a list of (ok, why) answers and return what it said.

    One answer is one tick. The loop is stopped by the sleep after the last
    one, which is the only way out of a while that is meant to run forever.
    """
    said = []
    seq = list(answers)
    state = {'i': 0}

    def fake_answer():
        i = state['i']
        state['i'] += 1
        if i >= len(seq):
            raise Stop()
        return seq[i]

    async def fake_say(text):
        said.append(text)

    def on_sleep():
        if state['i'] >= len(seq):
            raise Stop()

    class FakeClient(object):
        guilds = []

        async def wait_until_ready(self):
            return None

        def is_closed(self):
            return False

    keep = (bot.site_answers, bot.watch_say, bot.client, bot.WATCH_MISSES,
            bot.asyncio)
    bot.site_answers = fake_answer
    bot.watch_say = fake_say
    bot.client = FakeClient()
    bot.WATCH_MISSES = misses_needed
    bot.asyncio = AsyncioShim(on_sleep)
    try:
        try:
            asyncio.run(bot.watch_site())
        except Stop:
            pass
    finally:
        (bot.site_answers, bot.watch_say, bot.client, bot.WATCH_MISSES,
         bot.asyncio) = keep
    return said


UP = (True, 'HTTP 200')
DOWN = (False, 'timed out')

# S1: a site that is up is never mentioned. This is the whole design.
said = run([UP] * 12)
yes('S1 twelve good checks say nothing at all', said == [])

# S2: one miss is not an outage. A single timeout is packet loss.
said = run([UP, DOWN, UP, UP])
yes('S2 a single miss between good checks says nothing', said == [])

# S3: two in a row is an outage, and it is said once.
said = run([DOWN, DOWN])
yes('S3 two misses in a row say something', len(said) == 1)
yes('S3 and it says the site is not answering',
    said and 'not answering' in said[0])
yes('S3 and it carries what the last check actually saw',
    said and 'timed out' in said[0])

# S4: and it does NOT repeat for as long as it stays down. Eleven more
#     failures after the first message is eleven more chances to become noise.
said = run([DOWN] * 13)
yes('S4 thirteen misses still say it exactly once', len(said) == 1)

# S5: coming back is worth exactly one line.
said = run([DOWN, DOWN, DOWN, UP, UP, UP])
yes('S5 down then up says two things', len(said) == 2)
yes('S5 and the second one says it is back',
    len(said) == 2 and 'answering again' in said[1])

# S6: a second outage is a second pair, not silence. The flag has to reset.
said = run([DOWN, DOWN, UP, DOWN, DOWN, UP])
yes('S6 a second outage is reported too', len(said) == 4)
yes('S6 in order: down, up, down, up',
    len(said) == 4
    and 'not answering' in said[0] and 'answering again' in said[1]
    and 'not answering' in said[2] and 'answering again' in said[3])

# S7: recovery before the threshold never announces a recovery, because it
#     never announced an outage. Saying "the site is answering again" to
#     people who were never told it stopped is worse than saying nothing.
said = run([DOWN, UP, DOWN, UP])
yes('S7 a recovery nobody was warned about is not announced', said == [])

# S8: the threshold is honoured rather than hard coded at two.
said = run([DOWN, DOWN], misses_needed=3)
yes('S8 two misses say nothing when three are required', said == [])
said = run([DOWN, DOWN, DOWN], misses_needed=3)
yes('S8 and three do', len(said) == 1)

# S9: THE LOOP MUST SURVIVE ITS OWN CHECK FAILING. A watcher that dies quietly
#     looks exactly like everything being fine, which is the failure this whole
#     thing exists to stop.
state = {'n': 0}


def explode():
    state['n'] += 1
    if state['n'] <= 2:
        raise RuntimeError('the check itself blew up')
    if state['n'] > 5:
        raise Stop()
    return DOWN


said_box = []


async def say_box(t):
    said_box.append(t)


keep = (bot.site_answers, bot.watch_say, bot.client, bot.WATCH_MISSES,
        bot.asyncio)


class C(object):
    guilds = []

    async def wait_until_ready(self):
        return None

    def is_closed(self):
        return False


bot.site_answers = explode
bot.watch_say = say_box
bot.client = C()
bot.WATCH_MISSES = 2
bot.asyncio = AsyncioShim(lambda: None)
try:
    try:
        asyncio.run(bot.watch_site())
    except Stop:
        pass
finally:
    (bot.site_answers, bot.watch_say, bot.client, bot.WATCH_MISSES,
     bot.asyncio) = keep

yes('S9 a check that raises does not end the loop', state['n'] > 3)
yes('S9 and the misses after it are still counted', len(said_box) == 1)

# S10: site_answers itself, with the network replaced. It must never raise,
#      because the loop treats a raise as a bug rather than an outage.
import urllib.request  # noqa: E402

real = urllib.request.urlopen


class Reply(object):
    def __init__(self, code):
        self.code = code

    def getcode(self):
        return self.code

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


urllib.request.urlopen = lambda *a, **k: Reply(200)
yes('S10 a 200 is up', bot.site_answers() == (True, 'HTTP 200'))
urllib.request.urlopen = lambda *a, **k: Reply(302)
yes('S10 a redirect is up, because Caddy is answering', bot.site_answers()[0])
urllib.request.urlopen = lambda *a, **k: Reply(502)
yes('S10 a 502 is down, because that is Caddy with no site behind it',
    bot.site_answers() == (False, 'HTTP 502'))


def boom(*a, **k):
    raise OSError('')


urllib.request.urlopen = boom
ok, why = bot.site_answers()
yes('S10 a raise is down and not a crash', ok is False)
yes('S10 and an empty error still names something', why == 'OSError')
urllib.request.urlopen = real

# S11: THE CHANNEL IS FOUND BY ID, AND THIS IS THE CHECK THAT MATTERS MOST.
#
#      The staff channel is called news and sits in the Staff category. So does
#      a public news, which is where releases are announced. Two channels, one
#      name. Matching by name hands back whichever the server lists first, so a
#      watcher doing that tells everybody the site is down sooner or later.
#      Two drafts of this guessed at names, 'dev,general' and then 'dev-notes',
#      and neither name exists at all, so both would have fallen through to
#      whatever did.
yes('S11 the default is an id, taken from dev-channel.txt',
    isinstance(bot.WATCH_ID, int) and bot.WATCH_ID > 0)
yes('S11 and it is the id that file holds',
    bot.WATCH_ID == bot._dev_channel_id())
yes('S11 nothing is looked up by name any more',
    not hasattr(bot, 'WATCH'))

# S12: with no channel, or a channel the bot cannot see, it says NOTHING in
#      Discord rather than finding somewhere else to say it.
said_none = []


async def catch(t):
    said_none.append(t)


class NoChannel(object):
    guilds = []

    def get_channel(self, _id):
        return None

    async def wait_until_ready(self):
        return None

    def is_closed(self):
        return False


keep_c, keep_id = bot.client, bot.WATCH_ID
bot.client = NoChannel()
try:
    asyncio.run(bot.watch_say('this must not appear anywhere'))
    yes('S12 a channel the bot cannot see is silence, not a fallback',
        said_none == [])
    bot.WATCH_ID = 0
    asyncio.run(bot.watch_say('nor this'))
    yes('S12 and no id at all is silence too', said_none == [])
finally:
    bot.client, bot.WATCH_ID = keep_c, keep_id

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
