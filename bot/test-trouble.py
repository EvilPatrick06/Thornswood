"""
test-trouble.py

The staff-channel line for one session that went wrong, built by
bot._trouble_line out of a row the site wrote to trouble.json.

The thing worth testing is issue #532: a late upload must not read as a fresh
failure. A 401 held Patrick's 23 September logs until 14:09 the next day, when
a newer launcher uploaded the backlog, and the alert fired ~14:10 as if the
crash had just happened. So the line must name the session's OWN start time,
and when the logs arrived well after the session ended it must say so.

_trouble_line is a pure function of the row, so this drives it directly: no
Discord, no clock, no file. The real bot module is imported so a rename or a
reword fails here rather than in the channel.

Then where the line goes (#2940): #staff-updates by its id and nothing else.
No id, or an id the bot cannot see, is a line in the bot log and silence in
Discord, even with a channel called staff-general right there, which is
where it used to fall back to. And the send has every mention off. The
client and the channels are stand-ins that record what would have been sent.

Read only. Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.11 or newer, #2276)
import asyncio
import datetime
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# bot.py refuses to load without one, and never uses it unless client.run is
# called, which nothing here does.
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')

import bot  # noqa: E402
import discord  # noqa: E402

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


def ms(year, month, day, hour, minute):
    """Local unix ms, the way the site's Date.now() stamps a row, so it round
    trips through _clock's fromtimestamp whatever this box's timezone is."""
    return int(datetime.datetime(year, month, day, hour, minute).timestamp() * 1000)


# The incident from the issue, to the minute. Started the evening of the 23rd;
# the backlog was refused with 401 and did not land until 14:09 the next day.
start = ms(2026, 9, 23, 20, 7)
end = ms(2026, 9, 23, 21, 30)
arrived = ms(2026, 9, 24, 14, 9)

late = bot._trouble_line({
    'session': 'aaaa', 'name': 'Patrick Thornwood', 'channel': 'dev',
    'version': '1.1.91.10', 'start': start, 'end': end, 'at': arrived,
    'why': 'a script hit a ReferenceError',
    'line': 'ReferenceError: something is not defined',
})

yes('T1 the late alert names the session own start, not now',
    'started 20:07 on 23 September' in late)
yes('T2 and calls out when the logs actually arrived',
    'did not arrive until 14:09 on 24 September' in late)
yes('T3 and says in plain words it is a late upload, not a new failure',
    'late upload rather than a new failure' in late)
yes('T4 it still names who, the build and the launcher version',
    'Patrick Thornwood' in late and 'the dev build' in late
    and 'launcher 1.1.91.10' in late)
yes('T5 and still carries the reason and the line', 'ReferenceError' in late)

# A session whose logs arrive as it ends: the launcher's own end-of-session
# upload, the ordinary case. The start is named; the arrival is not called out,
# because there is nothing late about it.
prompt = bot._trouble_line({
    'session': 'bbbb', 'name': 'Someone', 'channel': 'main',
    'start': ms(2026, 9, 25, 10, 0), 'end': ms(2026, 9, 25, 10, 45),
    'at': ms(2026, 9, 25, 10, 45), 'why': 'the game crashed',
})
yes('T6 a prompt upload still names the session start',
    'started 10:00 on 25 September' in prompt)
yes('T7 and does not call the arrival late', 'did not arrive until' not in prompt)

# An older row, or one whose start was never seen: no start, no arrival, and it
# must not throw. The alert is poorer but still fires.
bare = bot._trouble_line({
    'session': 'cccc', 'who': '123', 'channel': '', 'why': 'the game crashed',
})
yes('T8 a row with no start drops the phrase rather than throwing',
    'It started' not in bare and 'A session went wrong' in bare)
yes('T9 and a row with no arrival gap is not called late',
    'did not arrive until' not in bare)

# _clock itself: the format the whole thing rests on, and its refusal to throw.
yes('T10 _clock reads a stamp as HH:MM on D Month',
    bot._clock(ms(2026, 9, 3, 8, 5)) == '08:05 on 3 September')
yes('T11 _clock gives nothing for a missing, zero or nonsense stamp',
    bot._clock(None) == '' and bot._clock('nope') == '' and bot._clock(0) == '')


# ----------------------------------------------------- where it is said --
SAID = []
bot.log = lambda *a: SAID.append(' '.join(str(x) for x in a))


class Channel(object):
    def __init__(self, cid, name):
        self.id = cid
        self.name = name
        self.sent = []

    async def send(self, text, **kw):
        self.sent.append((text, kw))


class Guild(object):
    def __init__(self, channels):
        self.text_channels = channels


class Client(object):
    def __init__(self, channels):
        self.guilds = [Guild(channels)]
        self.channels = channels

    def get_channel(self, cid):
        for c in self.channels:
            if c.id == cid:
                return c
        return None


def said_with(tid, text='A session went wrong.'):
    """trouble_say against a server with #staff-updates and #staff-general,
       with TROUBLE_ID set to tid. The two channels, and what was logged."""
    updates = Channel(1549254991082946570, 'staff-updates')
    general = Channel(1549254991082946571, 'staff-general')
    keep = bot.client, bot.TROUBLE_ID
    bot.client, bot.TROUBLE_ID = Client([updates, general]), tid
    SAID[:] = []
    try:
        asyncio.run(bot.trouble_say(text))
    finally:
        bot.client, bot.TROUBLE_ID = keep
    return updates, general, list(SAID)


updates, general, said = said_with(1549254991082946570, '@everyone ' + 'x' * 3000)
yes('C1 with the id it speaks in that channel, once',
    len(updates.sent) == 1 and not general.sent)
kw = updates.sent[0][1] if updates.sent else {}
am = kw.get('allowed_mentions')
yes('C2 and with every mention off, so an @everyone in the line pings nobody',
    isinstance(am, discord.AllowedMentions) and not am.everyone
    and not am.users and not am.roles)
yes('C3 and inside Discord\'s length',
    bool(updates.sent) and len(updates.sent[0][0]) <= 1900)

updates, general, said = said_with(0)
yes('C4 with no id nothing is said anywhere, staff-general included',
    not updates.sent and not general.sent)
yes('C5 and the bot log says the id is missing and what sends it',
    any('no channel id' in s and 'staff-channel.txt' in s for s in said))

updates, general, said = said_with(1234)
yes('C6 with an id the bot cannot see nothing is said anywhere either',
    not updates.sent and not general.sent)
yes('C7 and the bot log names that id',
    any('channel 1234 is not one this bot can see' in s for s in said))

# The comments still tell the story; the code holds no such name to look for.
src = open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
yes('C8 bot.py holds no channel name staff-general to fall back to',
    "'staff-general'" not in src and '"staff-general"' not in src)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
