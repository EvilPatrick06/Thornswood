"""
test-watch-services.py

The bot reading the VPS watchdog's log and saying what needs a person.

From the To Do List: "the sentence it writes when it gives up currently goes
to a file on the box that may itself be the thing that is gone". watch_services
in bot.py now reads that file, watch.log, and says three kinds of line in the
staff channel: needs a look, could not be started, did not come back.

The thing most worth testing is the same as in test-watch.py: that it SHUTS
UP. A service that will not stay up has a line written about it every five
minutes for as long as it is down, and a bot that repeats each one is a
channel nobody reads, which is the same as nobody being told.

And that it does not shut up for good. A fix made by hand leaves nothing in
the log but a run with no line about the service, and one that falls over
again must still be said (W16), or the person who fixed it believes it is
fixed.

The second is that the words it looks for are the words the watchdog writes.
They live in two files in two languages, so this reads Watch-Services.ps1,
renders the watchdog's own Note() lines out of it, and feeds those in. Change
the wording there and this fails, rather than the bot quietly hearing nothing.

The real bot module is imported and the real coroutine is run against a real
file in a temporary folder. Only Discord and the sleep are replaced.

Read only. Never connects to anything.
"""
import asyncio
import datetime
import os
import re
import shutil
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


def done():
    print('')
    print('%d passed, %d failed' % (len(PASS), len(FAIL)))
    sys.exit(1 if FAIL else 0)


# Before the change there is nothing to drive, and that is a failure to report
# rather than a traceback to read.
yes('bot.py reads the watchdog log at all',
    hasattr(bot, 'watch_log_news') and hasattr(bot, 'watch_services')
    and hasattr(bot, '_watch_log_lines'))
if FAIL:
    done()


# ------------------------------------------------ the watchdog's own words --
#
# The watcher is a single quoted here-string inside Watch-Services.ps1, written
# to the VPS as watch.ps1. Every line it writes goes through Note(), and every
# Note() is a string of literals and variables joined with +, so it can be
# rendered here exactly as the box would write it.
PS1 = os.path.join(HERE, '..', 'scripts', 'vps', 'Watch-Services.ps1')
src = open(PS1, encoding='utf-8').read()
a = src.index("$watcher = @'")
watchdog = src[a:src.index("\n'@", a)]

yes('W1 the watchdog stamps each line yyyy-MM-dd HH:mm:ss',
    "$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')" in watchdog)
yes('W1 and puts two spaces between the stamp and the line',
    "($stamp + '  ' + $line)" in watchdog)

VARS = {'$c.Name': '{name}', '$already': '3', '$rc': '1',
        '$c.Task': 'Thornswood Server'}
TOKEN = r"'([^']*)'|(\$[A-Za-z_][\w.]*)"


def render(expr):
    """One Note() argument as the watchdog would write it, or None."""
    if re.sub(TOKEN, '', expr).strip(' +'):
        return None
    out = []
    for lit, var in re.findall(TOKEN, expr):
        if var:
            if var not in VARS:
                return None
            out.append(VARS[var])
        else:
            out.append(lit)
    return ''.join(out)


SAYS = {}
for expr in re.findall(r"\bNote \(([^()]*)\)", watchdog):
    text = render(expr)
    if text is None:
        continue
    for kind, frag in (('look', 'needs a look'),
                       ('refused', 'could not be started'),
                       ('stuck', 'did not come back'),
                       ('trying', 'is not answering'),
                       ('back', ' is back')):
        if frag in text:
            SAYS[kind] = text
            break

for kind in ('look', 'refused', 'stuck', 'trying', 'back'):
    yes('W1 the watchdog still writes its "%s" line' % kind, kind in SAYS)
if FAIL:
    done()

BASE = datetime.datetime(2026, 9, 24, 20, 0, 0)


def line(minutes, kind, name='game'):
    """A watch.log line, `minutes` after BASE, in the watchdog's own words."""
    t = BASE + datetime.timedelta(seconds=int(round(minutes * 60)))
    return t.strftime('%Y-%m-%d %H:%M:%S') + '  ' + SAYS[kind].replace('{name}', name)


def news(lines, state=None):
    return bot.watch_log_news(lines, {} if state is None else state)


# -------------------------------------------------- each line on its own --
said = news([line(0, 'stuck')])
yes('W2 "did not come back" is said', len(said) == 1)
yes('W2 and names the service', said and said[0].startswith('**Game did not come back'))
yes('W2 and carries the watch.log line exactly as written',
    said and line(0, 'stuck') in said[0])

said = news([line(0, 'refused')])
yes('W3 "could not be started" is said', len(said) == 1)
yes('W3 and carries the task name out of the line',
    said and 'Is the task called Thornswood Server ?' in said[0])

said = news([line(0, 'look')])
yes('W4 "needs a look" is said', len(said) == 1)
yes('W4 and says how many restarts it had',
    said and 'restarted 3 times this hour' in said[0])

yes('W5 "is not answering, starting" alone says nothing',
    news([line(0, 'trying')]) == [])
yes('W5 "is back" alone says nothing', news([line(0, 'back')]) == [])
yes('W5 a restart that worked says nothing, because it needed nobody',
    news([line(0, 'trying'), line(0.4, 'back')]) == [])

# ------------------------------------------------- THE ONE THIS IS FOR --
#
# One service that will not stay up, for an hour and a half, exactly the way
# the watchdog writes it: a restart that fails on each of three runs, then
# "needs a look" on every run until the hour since the first restart is up,
# then another restart, and round again. Twenty four lines, and a person needs
# to hear three things: that it did not come back, that it has been given up
# on, and an hour after that, that it still has.
broken = []
for m in (0, 5, 10, 60, 65, 70):
    broken += [line(m, 'trying'), line(m + 0.4, 'stuck')]
for m in list(range(15, 60, 5)) + [75, 80, 85]:
    broken.append(line(m, 'look'))
broken.sort()
said = news(broken)
yes('W6 a service down for ninety minutes is three messages, not %d' % len(broken),
    len(said) == 3)
yes('W6 in order: it did not come back, then it needs a look',
    len(said) == 3 and 'did not come back' in said[0] and 'needs a look' in said[1])
yes('W6 and an hour after that, that it still needs a look',
    len(said) == 3 and said[2].startswith('**Game still needs a look')
    and 'said here 60 minutes ago' in said[2]
    and line(75, 'look') in said[2])

state = {}
one_at_a_time = []
for ln in broken:
    one_at_a_time += news([ln], state)
yes('W6 and the same when the lines arrive one read at a time',
    one_at_a_time == said)

# ------------------------------------------------ when an outage is over --
said = news([line(0, 'stuck'), line(25, 'trying'), line(25.4, 'stuck')])
yes('W7 twenty five minutes with no word about it, and the next one is said again',
    len(said) == 2)

# The watchdog runs every five minutes and writes nothing about a service that
# answers, so ten minutes between lines is one run that found it up.
said = news([line(0, 'look'), line(10, 'look')])
yes('W7 one run that found it answering ends the outage', len(said) == 2)
said = news([line(0, 'look'), line(5, 'look'), line(10, 'look')])
yes('W7 but one run to the next is the same outage', len(said) == 1)
# The run before a line can be slow, when it is restarting the services
# checked ahead of this one, and a restart sleeps before its second line.
said = news([line(0, 'trying'), line(0.75, 'stuck'), line(7, 'trying'),
             line(7.75, 'stuck')])
yes('W7 and so is a run that got to it a couple of minutes late', len(said) == 1)

said = news([line(0, 'stuck'), line(5, 'trying'), line(5.4, 'back'),
             line(10, 'trying'), line(10.4, 'stuck')])
yes('W8 the watchdog writing that it is back ends the outage', len(said) == 2)

# Fourteen minutes between the two "did not come back", which on their own
# would be two outages. The "Starting" lines in between are the watchdog
# writing about it on every run, so it is one.
said = news([line(0, 'stuck'), line(5, 'trying'), line(10, 'trying'),
             line(14, 'stuck')])
yes('W9 a line saying it is being started again counts as more of the same',
    len(said) == 1)

# ------------------------------------------------ two services at once --
said = news([line(0, 'stuck', 'game'), line(0.5, 'stuck', 'dev game'),
             line(15, 'look', 'game'), line(15.2, 'look', 'dev game')])
yes('W10 two services down together are counted apart', len(said) == 4)
yes('W10 and dev game is not taken for game',
    len(said) == 4 and said[1].startswith('**Dev game')
    and said[3].startswith('**Dev game'))

# ------------------------------------------------ what is not its business --
state = {}
try:
    said = news(['', 'garbage', '2026-09-24 20:00:00', '2026-09-24 20:00:00  ',
                 'game did not come back in time',
                 '2026-13-45 99:99:99  game did not come back in time',
                 '2026-09-24 20:00:00  somebody wrote something else'], state)
    raised = False
except Exception:
    raised = True
yes('W11 lines that are not the watchdog\'s are ignored, and nothing raises',
    not raised and said == [])

long_line = line(0, 'refused').replace('Thornswood Server', 'x' * 5000)
said = news([long_line])
yes('W11 a message is never longer than Discord takes',
    len(said) == 1 and len(said[0]) <= 1900)

# -------------------------------------------------- a restart of the bot --
state = {}
news([line(0, 'trying'), line(0.4, 'stuck'), line(5, 'trying'),
      line(5.4, 'stuck'), line(10, 'trying'), line(10.4, 'stuck'),
      line(15, 'look')], state)
said = news([line(m, 'look') for m in range(20, 60, 5)]
            + [line(60, 'trying'), line(60.4, 'stuck')], state)
yes('W12 an outage already in the log when the bot starts stays quiet',
    said == [])

state = {}
news([line(0, 'stuck')], state)
said = news([line(5, 'look')], state)
yes('W12 but what it had not reached yet is still said', len(said) == 1)

state = {}
news([line(0, 'stuck'), line(5, 'look')]
     + [line(m, 'look') for m in range(10, 60, 5)], state)
said = news([line(60, 'look'), line(65, 'look')], state)
yes('W12 and the hourly reminder still comes, timed from the log, not the bot',
    len(said) == 1 and 'still needs a look' in said[0])

# ------------------------------------------------------ reading the file --
TMP = tempfile.mkdtemp(prefix='thornswood-watchlog-')
keep_log = bot.WATCH_LOG
try:
    path = os.path.join(TMP, 'watch.log')
    bot.WATCH_LOG = path
    yes('W13 no file is an empty log, which is a quiet box',
        bot._watch_log_lines() == [])

    with open(path, 'wb') as f:
        f.write(b'\xef\xbb\xbf' + line(0, 'stuck').encode() + b'\r\n\r\n'
                + line(1, 'back').encode() + b'\r\n')
    got = bot._watch_log_lines()
    yes('W13 the byte order mark the trim leaves is not part of the first line',
        got and got[0] == line(0, 'stuck'))
    yes('W13 and line endings and blank lines are gone',
        got == [line(0, 'stuck'), line(1, 'back')])

    with open(path, 'ab') as f:
        f.write(line(2, 'refused').encode()[:30])
    yes('W13 half a line is left for the next read',
        bot._watch_log_lines() == [line(0, 'stuck'), line(1, 'back')])

    bot.WATCH_LOG = TMP
    yes('W13 a file that cannot be read is None, not an empty log',
        bot._watch_log_lines() is None)
finally:
    bot.WATCH_LOG = keep_log


# ------------------------------------------------ the loop, end to end --
class AsyncioShim(object):
    """Everything asyncio does, except sleeping. The same as test-watch.py."""

    def __init__(self, on_sleep):
        self._on_sleep = on_sleep

    def __getattr__(self, name):
        return getattr(asyncio, name)

    async def sleep(self, _seconds):
        return self._on_sleep()


class Stop(BaseException):
    """Ends the loop. BaseException, because the loop catches Exception."""


class Channel(object):
    def __init__(self, cid, name, box):
        self.id = cid
        self.name = name
        self._box = box

    async def send(self, text):
        self._box.append((self.id, text))


STAFF_ID = 424242
posted = []
public = []


class Guild(object):
    # A public channel with the same name as the staff one, which is what this
    # server actually has. Anything that lands here is the failure.
    text_channels = [Channel(1, 'news', public)]


class FakeClient(object):
    guilds = [Guild()]
    asked = []

    async def wait_until_ready(self):
        return None

    def is_closed(self):
        return False

    def get_channel(self, cid):
        self.asked.append(cid)
        return Channel(STAFF_ID, 'news', posted) if cid == STAFF_ID else None


def append(path, text):
    with open(path, 'ab') as f:
        f.write(text.encode('utf-8'))


def raising():
    raise RuntimeError('the read itself blew up')


path = os.path.join(TMP, 'watch.log')
with open(path, 'wb') as f:
    # Yesterday's trouble, already in the file when the bot starts.
    f.write(b'\xef\xbb\xbf')
for ln in (line(-1440, 'trying', 'voice'), line(-1439.6, 'stuck', 'voice'),
           line(-1425, 'look', 'voice')):
    append(path, ln + '\r\n')

real_read = bot._watch_log_lines
half = line(5, 'refused')


def step0():
    append(path, line(0, 'trying') + '\r\n' + line(0.4, 'stuck') + '\r\n')


def step1():
    append(path, half[:40])


def step2():
    append(path, half[40:] + '\r\n')


def step3():
    bot.WATCH_LOG = TMP


def step4():
    # The watchdog trimming its file: rewritten, shorter, byte order mark
    # first, every line that is left already said.
    bot.WATCH_LOG = path
    with open(path, 'rb') as f:
        kept = f.read().decode('utf-8-sig').split('\r\n')[-3:]
    with open(path, 'wb') as f:
        f.write(b'\xef\xbb\xbf' + '\r\n'.join(kept).encode('utf-8'))


def step5():
    bot._watch_log_lines = raising


def step6():
    bot._watch_log_lines = real_read
    append(path, line(6, 'trying', 'dev game') + '\r\n'
           + line(6.4, 'stuck', 'dev game') + '\r\n')


def step7():
    append(path, line(15, 'look') + '\r\n' + line(20, 'look') + '\r\n')


steps = [step0, step1, step2, step3, step4, step5, step6, step7]
after = []


def on_sleep():
    after.append(len(posted))
    i = len(after) - 1
    if i >= len(steps):
        raise Stop()
    steps[i]()


keep = (bot.client, bot.WATCH_ID, bot.WATCH_LOG, bot.asyncio,
        bot._watch_log_lines)
bot.client = FakeClient()
bot.WATCH_ID = STAFF_ID
bot.WATCH_LOG = path
bot.asyncio = AsyncioShim(on_sleep)
try:
    try:
        asyncio.run(bot.watch_services())
    except Stop:
        pass
finally:
    (bot.client, bot.WATCH_ID, bot.WATCH_LOG, bot.asyncio,
     bot._watch_log_lines) = keep
    shutil.rmtree(TMP, ignore_errors=True)

texts = [t for _, t in posted]
# after[i] is how many had been posted when read i finished.
yes('W14 what was already in the log when the bot started is not said',
    after[:1] == [0])
yes('W14 a restart that did not come back is said on the next read',
    after[1:2] == [1] and 'Game did not come back' in texts[0])
yes('W14 half a line says nothing until it is whole', after[2:3] == [1])
yes('W14 and then it is said once, the whole line',
    after[3:4] == [2] and half in texts[1])
yes('W14 a read that fails says nothing and replays nothing',
    after[4:5] == [2])
yes('W14 the watchdog trimming its file replays nothing', after[5:6] == [2])
yes('W14 a read that raises does not end the loop',
    after[6:7] == [2] and len(after) == 9)
yes('W14 the next service down is said after that',
    after[7:8] == [3] and 'Dev game did not come back' in texts[2])
yes('W14 two "needs a look" in one read are one message',
    after[8:9] == [4] and 'needs a look' in texts[3])
yes('W14 every message went to the staff channel, found by id',
    posted and all(cid == STAFF_ID for cid, _ in posted)
    and set(FakeClient.asked) == set([STAFF_ID]))
yes('W14 AND NOTHING WENT TO THE PUBLIC CHANNEL WITH THE SAME NAME',
    public == [])

# ------------------------------------------------- it is actually started --
src_bot = open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
guard = src_bot[src_bot.index('    if not _watching:'):src_bot.index("    log('up as")]
yes('W15 on_ready starts it, once, beside the other watchers',
    'asyncio.create_task(watch_services())' in guard)
# The function ends at the next line that starts in the first column. It used
# to run to the comment above on_ready, which held while nothing else sat
# between them; main's report watcher now does, and its own .send( was being
# read as this one's.
_start = src_bot.index('async def watch_services():')
body = src_bot[_start:re.compile(r'^\S', re.M).search(src_bot, _start + 1).start()]
yes('W15 and it speaks only through watch_say, which has no public fallback',
    'watch_say(' in body and '.send(' not in body and 'by_name' not in body)

# ------------------------------------------ a fix by hand that does not hold --
#
# Found by a reviewer on 24 September, traced with this function as it was
# then. The game gets "did not come back" at 11:20, 11:25 and 11:30 and "needs
# a look" every five minutes to 12:00. A person fixes it by hand at 12:02, the
# 12:05 run finds it up and writes nothing, and it falls over at 12:08. The
# watchdog's restart history still holds the three from 11:20 to 11:30, so the
# 12:10 run writes "needs a look" straight away, then restarts it as those age
# out, then gives up again. A line every five minutes, and with twenty minutes
# of quiet needed to end an outage, nothing at all was said for seventy
# minutes. The person who fixed it believed it was fixed.
HAND = datetime.datetime(2026, 9, 24, 11, 0, 0)


def at(minutes, kind):
    """A watch.log line about the game, `minutes` after 11:00."""
    return line((HAND - BASE).total_seconds() / 60 + minutes, kind)


def first_outage(state):
    """11:20 to 12:00: three restarts that fail, then given up on."""
    said = []
    for m in (20, 25, 30):
        said += news([at(m, 'trying'), at(m + 0.4, 'stuck')], state)
    for m in range(35, 61, 5):
        said += news([at(m, 'look')], state)
    return said


state = {}
yes('W16 the first outage is said, twice', len(first_outage(state)) == 2)

again = []
timeline = [(70, 'look'), (75, 'look'), (80, 'trying'), (80.4, 'stuck'),
            (85, 'trying'), (85.4, 'stuck'), (90, 'trying'), (90.4, 'stuck'),
            (95, 'look'), (100, 'look'), (105, 'look'), (110, 'look'),
            (115, 'look'), (120, 'look'), (125, 'look'), (130, 'look'),
            (135, 'look'), (140, 'trying'), (140.4, 'stuck')]
for m, k in timeline:
    again.append(news([at(m, k)], state))
yes('W16 A FIX BY HAND THAT HELD ONE RUN AND THEN FELL OVER IS SAID, on the '
    'first line after the run that found it up',
    len(again[0]) == 1 and 'needs a look' in again[0][0]
    and at(70, 'look') in again[0][0])
said = [t for batch in again for t in batch]
yes('W16 and it is a few messages across seventy minutes, not none and not '
    'one for each of the %d lines' % len(timeline),
    2 <= len(said) <= 4)

# The same fix falling over before the watchdog's next run, so there is no
# clean run and no gap. Nothing in the log can tell that apart from the
# service never having come back, so this is what the hourly reminder is for:
# the person hears it within the hour of the last time it was said.
state = {}
first_outage(state)
quick = {}
for m in range(65, 100, 5):
    quick[m] = news([at(m, 'look')], state)
hits = sorted(m for m in quick if quick[m])
yes('W16 a fix that falls over before the next run is said within the hour',
    hits == [95])
yes('W16 and says it was said before, and how long ago',
    hits == [95] and len(quick[95]) == 1
    and 'said here 60 minutes ago' in quick[95][0])

done()
