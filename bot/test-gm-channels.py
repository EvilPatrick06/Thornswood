"""
test-gm-channels.py

The Gamemasters category is for the gamemaster ranks only.

From the GM Rules (v1.0, section 10): a private GM area with
#gm-scene-summaries, #gm-chat, #gm-suggestions and a GM voice channel.
Djinn, 14 Oct 2026: "there should be NO public channel inside the GM
channel area. GM only."

Holds:

  G1 Build-Discord.py has a Gamemasters category with the four channels
  G2 every channel in it is mode gm, and nothing public, open, read or
     membersread sits in it
  G3 a category this makes gets gm too, the same as its channels
  G4 gm shuts @everyone out of seeing it
  G5 gm lets in Lead Gamemaster, Gamemaster and Trial Gamemaster to see,
     talk and read back
  G6 gm grants nothing to Member, Moderator, Loremaster, Playtester, Dev or
     Owner (Owner and Dev see it through Administrator, not through this)
  G7 the bot is named, so it keeps the channels without Administrator
  G8 a lead role spelled 'Lead GM' is found as well, and a GM role that is
     not on the server is passed over rather than stopping the build

Build-Discord.py is imported for real, under another name, so its __main__
block never runs. Read only. Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.10 or newer, #2276)
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
want = [('text', 'gm-scene-summaries'), ('text', 'gm-chat'),
        ('text', 'gm-suggestions'), ('voice', 'GM Voice')]
yes('G1 it holds #gm-scene-summaries, #gm-chat, #gm-suggestions and GM Voice '
    '(got %r)' % [(s['kind'], s['name']) for s in gm],
    [(s['kind'], s['name']) for s in gm] == want)

# ------------------------------------------------------------------ G2 --
yes('G2 every channel in Gamemasters is gm',
    bool(gm) and all(s.get('mode') == 'gm' for s in gm))
yes('G2 nothing public, open, read or membersread is in Gamemasters',
    not any(s.get('mode', 'open') in ('public', 'open', 'read', 'membersread')
            for s in gm))
yes('G2 no other category carries a gm channel',
    not any(s.get('mode') == 'gm'
            for cat, specs in B.PLAN if cat != 'Gamemasters' for s in specs))

# ------------------------------------------------------------------ G3 --
m = re.search(r"mode = \{'Staff': 'staff', 'Testing': 'pathfind',(.*?)\}\.get\(catname, 'open'\)",
              SRC, re.S)
yes('G3 a Gamemasters category this makes is gm, not the open default',
    m is not None and "'Gamemasters': 'gm'" in m.group(1))

# ------------------------------------------------------------- G4 to G7 --
NAMES = ['Owner', 'Lead Gamemaster', 'Dev', 'Gamemaster', 'Loremaster',
         'Trial Gamemaster', 'Moderator', 'Playtester', 'Member']
guild, roles = server(NAMES)
ow = B.overwrites(guild, 'gm', roles)

ev = ow.get(guild.default_role)
yes('G4 @everyone cannot see a gm channel',
    ev is not None and ev.view_channel is False)

for n in ('Lead Gamemaster', 'Gamemaster', 'Trial Gamemaster'):
    o = ow.get(roles[n])
    yes('G5 %s sees, talks and reads back' % n,
        o is not None and o.view_channel is True and o.send_messages is True
        and o.read_message_history is True)

for n in ('Member', 'Moderator', 'Loremaster', 'Playtester', 'Dev', 'Owner'):
    yes('G6 %s is granted nothing in a gm channel' % n, roles[n] not in ow)

others = [k for k in ow if k is not guild.default_role
          and getattr(k, 'name', None) not in ('Lead Gamemaster', 'Gamemaster',
                                               'Trial Gamemaster')]
yes('G7 the only other entry is the bot itself (got %r)' % others,
    others == [guild.me] and granted(ow, guild.me))

# ------------------------------------------------------------------ G8 --
guild2, roles2 = server(['Lead GM', 'Gamemaster'])
ow2 = B.overwrites(guild2, 'gm', roles2)
yes("G8 a lead role spelled 'Lead GM' is let in", granted(ow2, roles2['Lead GM']))
yes('G8 Trial Gamemaster missing from the server is passed over, not fatal',
    granted(ow2, roles2['Gamemaster'])
    and not any(getattr(k, 'name', '') == 'Trial Gamemaster' for k in ow2))

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
