"""
test-gm-channels.py

The Gamemasters category is for the gamemaster ranks and Moderator only.

Djinn's layout of 15 Oct 2026, confirmed by him on 17 Oct (#2519): visible to
Lead Gamemaster, Gamemaster, Trial Gamemaster and Moderator (Owner and Dev
through Administrator), @everyone denied, nothing public. #gm-rules is read
only except for Lead Gamemaster, Owner and Dev; #gm-scene-summaries, #gm-chat,
#gm-suggestions, #gm-discipline (kept from 14 Oct) and GM Voice are for
everybody in it.

Holds:

  G1 Build-Discord.py has a Gamemasters category with those six, in that
     order, and the old #gm only as make=False
  G2 every channel in it is gm or gmrules, and nothing public, open, read or
     membersread sits in it, and no other category carries either
  G3 a category this makes gets gm too, the same as its channels
  G4 gm and gmrules shut @everyone out of seeing them
  G5 gm lets Lead Gamemaster, Gamemaster, Trial Gamemaster and Moderator
     see, talk and read back
  G6 gm grants nothing to Member, Loremaster, Playtester, Dev or Owner
     (Owner and Dev see it through Administrator, not through this)
  G7 the bot is named, so it keeps the channels without Administrator
  G8 a lead role spelled 'Lead GM' is found as well, and a GM role that is
     not on the server is passed over rather than stopping the build
  G9 gmrules: the GM area reads and cannot post, start threads or post in
     them; Lead Gamemaster, Owner and Dev post; Member and the rest get
     nothing

Build-Discord.py is imported for real, under another name, so its __main__
block never runs. Read only. Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.11 or newer, #2276)
import importlib.util
import os
import re
import sys
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
    'build_discord_gm', os.path.join(HERE, 'Build-Discord.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

SRC = open(os.path.join(HERE, 'Build-Discord.py'), encoding='utf-8').read()


class Role(object):
    def __init__(self, name, rid):
        self.name = name
        self.id = rid

    def __repr__(self):
        return '<role %s>' % self.name


def server(names):
    everyone = Role('@everyone', 1)
    rs = [everyone] + [Role(n, 10 + i) for i, n in enumerate(names)]
    bot = Role('Thornswood Bot', 999)
    guild = types.SimpleNamespace(default_role=everyone, me=bot, roles=rs)
    return guild, dict((r.name, r) for r in rs)


def granted(ow, role):
    o = ow.get(role)
    return o is not None and o.view_channel is True


# ------------------------------------------------------------------ G1 --
plan = dict(B.PLAN)
gm = plan.get('Gamemasters')
yes('G1 Build-Discord.py has a Gamemasters category', gm is not None)
gm = gm or []
made = [s for s in gm if s.get('make', True)]
want = [('text', 'gm-rules'), ('text', 'gm-scene-summaries'), ('text', 'gm-chat'),
        ('text', 'gm-suggestions'), ('text', 'gm-discipline'), ('voice', 'GM Voice')]
yes('G1 it makes #gm-rules, #gm-scene-summaries, #gm-chat, #gm-suggestions, '
    '#gm-discipline and GM Voice (got %r)' % [(s['kind'], s['name']) for s in made],
    [(s['kind'], s['name']) for s in made] == want)
yes('G1 the 14 Oct #gm is named only so prune leaves it, never made',
    [(s['name'], s.get('make', True)) for s in gm if not s.get('make', True)] == [('gm', False)])
yes('G1 every one of them is in KEEP',
    all(s['name'].lower() in B.KEEP for s in gm))

# ------------------------------------------------------------------ G2 --
yes('G2 every channel in Gamemasters is gm, and only #gm-rules is gmrules',
    bool(gm) and all(s.get('mode') == ('gmrules' if s['name'] == 'gm-rules' else 'gm') for s in gm))
yes('G2 nothing public, open, read or membersread is in Gamemasters',
    not any(s.get('mode', 'open') in ('public', 'open', 'read', 'membersread')
            for s in gm))
yes('G2 no other category carries a gm channel',
    not any(s.get('mode') in ('gm', 'gmrules')
            for cat, specs in B.PLAN if cat != 'Gamemasters' for s in specs))

# ------------------------------------------------------------------ G3 --
# Read off the builder's own table (CATEGORY_MODE, #3317), which both the build
# and the audit use, rather than off its source.
yes('G3 a Gamemasters category this makes is gm, not the open default',
    B.CATEGORY_MODE.get('Gamemasters') == 'gm')

# ------------------------------------------------------------- G4 to G7 --
NAMES = ['Owner', 'Lead Gamemaster', 'Dev', 'Gamemaster', 'Loremaster',
         'Trial Gamemaster', 'Moderator', 'Playtester', 'Member']
guild, roles = server(NAMES)
ow = B.overwrites(guild, 'gm', roles)

ev = ow.get(guild.default_role)
yes('G4 @everyone cannot see a gm channel',
    ev is not None and ev.view_channel is False)

for n in ('Lead Gamemaster', 'Gamemaster', 'Trial Gamemaster', 'Moderator'):
    o = ow.get(roles[n])
    yes('G5 %s sees, talks and reads back' % n,
        o is not None and o.view_channel is True and o.send_messages is True
        and o.read_message_history is True)

for n in ('Member', 'Loremaster', 'Playtester', 'Dev', 'Owner'):
    yes('G6 %s is granted nothing in a gm channel' % n, roles[n] not in ow)

others = [k for k in ow if k is not guild.default_role
          and getattr(k, 'name', None) not in ('Lead Gamemaster', 'Gamemaster',
                                               'Trial Gamemaster', 'Moderator')]
yes('G7 the only other entry is the bot itself (got %r)' % others,
    others == [guild.me] and granted(ow, guild.me))

# ------------------------------------------------------------------ G8 --
guild2, roles2 = server(['Lead GM', 'Gamemaster'])
ow2 = B.overwrites(guild2, 'gm', roles2)
yes("G8 a lead role spelled 'Lead GM' is let in", granted(ow2, roles2['Lead GM']))
yes('G8 Trial Gamemaster missing from the server is passed over, not fatal',
    granted(ow2, roles2['Gamemaster'])
    and not any(getattr(k, 'name', '') == 'Trial Gamemaster' for k in ow2))

# ------------------------------------------------------------------ G9 --
rw = B.overwrites(guild, 'gmrules', roles)
e9 = rw.get(guild.default_role)
yes('G4 @everyone cannot see #gm-rules', e9 is not None and e9.view_channel is False)
for n in ('Gamemaster', 'Trial Gamemaster', 'Moderator'):
    o = rw.get(roles[n])
    yes('G9 %s reads #gm-rules and cannot post, start a thread or post in one' % n,
        o is not None and o.view_channel is True and o.read_message_history is True
        and o.send_messages is False and o.create_public_threads is False
        and o.send_messages_in_threads is False)
for n in ('Lead Gamemaster', 'Owner', 'Dev'):
    o = rw.get(roles[n])
    yes('G9 %s posts in #gm-rules' % n,
        o is not None and o.view_channel is True and o.send_messages is True)
for n in ('Member', 'Loremaster', 'Playtester'):
    yes('G9 %s is granted nothing in #gm-rules' % n, roles[n] not in rw)
yes('G9 the bot is named in #gm-rules', granted(rw, guild.me))

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
