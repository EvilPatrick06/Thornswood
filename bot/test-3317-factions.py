"""
test-3317-factions.py

The sixteen factions in Discord (#3317).

Patrick, 22 Oct 2026, on the page: 16 factions (q-3317-faction-roster, B),
each with a member role and a Leader role (q-3317-faction-roles, A), the
Leader giving the member role (q-3317-faction-member-give, A), a channel per
faction and #seats (q-3317-faction-channels), and every faction's 4E 252
entry in lore/factions.md, which he approved the same day. This proves:

  F1 factions.json is the sixteen, and each has a member role (its short
     name) and a Leader role, the Leader a seat and the member not
  F2 the Trading Company role is renamed to the company's member role, so
     everybody holding it keeps it; Business Owner is in the plan
  F3 the Factions category: #seats, then one channel per faction, in the
     order of factions.json, after the holds and before Voice
  F4 a faction's channel: its members and its Leader talk; another
     faction's members and Leader get nothing; FACTION_STAFF talks; a
     Playtester with no faction gets nothing; @everyone sees none
  F5 #seats: every Jarl and faction Leader and the council talk; a faction
     member, a Citizen and a Gamemaster get nothing
  F6 lore/factions.md has an entry for every faction, by its short name

Build-Discord.py is imported for real, under another name, so its __main__
block never runs. Read only. Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.11 or newer, #2276)
import importlib.util
import json
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


SIXTEEN = ['Imperial Embassy', 'Thalmor Remnant', 'Free Skyrim Trading Company',
           'The Companions', 'College of Winterhold', 'Bards College',
           'Thieves Guild', 'Dark Brotherhood', 'Vigilants of Stendarr',
           'Dawnguard', 'Silver Hand', 'Forsworn', 'Orc Strongholds',
           'Khajiit Caravans', 'Blades', 'Volkihar Clan']

with open(os.path.join(HERE, 'factions.json'), encoding='utf-8') as f:
    yes('F1 factions.json is the sixteen of lore/factions.md, in its order',
        json.load(f) == SIXTEEN)

with open(os.path.join(HERE, '..', 'lore', 'factions.md'), encoding='utf-8') as f:
    lore = f.read()

try:
    import discord  # noqa: F401
except ImportError:
    print('SKIP  discord.py is not installed here, so the builder cannot be imported')
    print('')
    print('%d passed, %d failed' % (len(PASS), len(FAIL)))
    sys.exit(1 if FAIL else 0)

spec = importlib.util.spec_from_file_location(
    'build_discord_factions', os.path.join(HERE, 'Build-Discord.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)


class Role(object):
    def __init__(self, name, rid):
        self.name = name
        self.id = rid

    def __repr__(self):
        return '<role %s>' % self.name


everyone = Role('@everyone', 1)
rs = [everyone] + [Role(n, 10 + i) for i, (n, _, _, _) in enumerate(B.ROLES)]
guild = types.SimpleNamespace(default_role=everyone, me=Role('Thornswood Bot', 999), roles=rs)
roles = dict((r.name, r) for r in rs)
plan = dict(B.PLAN)


def can(ow, name):
    """'talk', 'read' or None for a role in a set of overwrites."""
    o = ow.get(roles[name])
    if o is None or o.view_channel is not True:
        return None
    return 'talk' if o.send_messages is not False else 'read'


# ------------------------------------------------------------------ F1 --
names = [n for n, _, _, _ in B.ROLES]
hoist = dict((n, h) for n, _, h, _ in B.ROLES)
yes('F1 every faction has its member role, by its short name',
    list(B.FACTION_MEMBERS) == [B.FACTION_SHORT.get(f, f) for f in SIXTEEN]
    and all(m in names for m in B.FACTION_MEMBERS))
yes('F1 every faction has its Leader role, a seat, shown on its own',
    all(n in names and n in B.SEATS and hoist[n] for n in B.FACTION_LEADERS)
    and len(B.FACTION_LEADERS) == 16)
yes('F1 a member role is no seat and not shown on its own',
    not any(m in B.SEATS or hoist[m] for m in B.FACTION_MEMBERS))
yes('F1 the short names are the two the application always used',
    B.FACTION_MEMBERS[1] == 'Thalmor' and B.FACTION_MEMBERS[3] == 'Companions')

# ------------------------------------------------------------------ F2 --
yes('F2 Trading Company is renamed to Free Skyrim Trading Company, never made twice',
    B.ROLE_WAS.get('Free Skyrim Trading Company') == ('Trading Company',)
    and 'Trading Company' not in names)
yes('F2 Business Owner is in the plan, with nothing of its own',
    'Business Owner' in names
    and dict((n, p) for n, _, _, p in B.ROLES)['Business Owner'].value == 0)

# ------------------------------------------------------------------ F3 --
cats = [c for c, _ in B.PLAN]
yes('F3 Factions sits after the last hold and before Voice',
    cats.index('Factions') == cats.index(B.HOLDS[-1]) + 1
    and cats.index('Voice') == cats.index('Factions') + 1)
got = [(s['name'], s.get('mode'), s.get('faction')) for s in plan['Factions']]
yes('F3 #seats, then one channel per faction in the order of factions.json',
    got == [('seats', 'seats', None)] +
    [(B.faction_slug(f), 'faction', f) for f in SIXTEEN])
yes('F3 the channel names are plain: #companions, #free-skyrim-trading-company',
    B.faction_slug('The Companions') == 'companions'
    and B.faction_slug('Free Skyrim Trading Company') == 'free-skyrim-trading-company')

# ------------------------------------------------------------------ F4 --
places = dict((s['name'], B.spec_overwrites(guild, s, roles)) for s in plan['Factions'])
comp = places['companions']
yes('F4 #companions: Companions and Companions Leader talk',
    can(comp, 'Companions') == 'talk' and can(comp, 'Companions Leader') == 'talk')
yes('F4 #companions: the Silver Hand, its Leader and a Thalmor get nothing',
    can(comp, 'Silver Hand') is None and can(comp, 'Silver Hand Leader') is None
    and can(comp, 'Thalmor') is None)
yes('F4 #companions: the council, the gamemasters and the Loremasters talk',
    all(can(comp, n) == 'talk' for n in B.FACTION_STAFF)
    and 'Loremaster' in B.FACTION_STAFF and 'Trial Gamemaster' in B.FACTION_STAFF)
yes('F4 #companions: a Playtester, a Moderator and a Jarl get nothing',
    can(comp, 'Playtester') is None and can(comp, 'Moderator') is None
    and can(comp, 'Jarl of Whiterun') is None)
yes('F4 @everyone sees none of the Factions channels',
    all(ow[everyone].view_channel is False for ow in places.values()))
cow = B.category_overwrites(guild, 'Factions', roles)
yes('F4 the Factions category: FACTION_STAFF only, @everyone out',
    B.category_mode('Factions') == ('faction', None)
    and all(can(cow, n) == 'talk' for n in B.FACTION_STAFF)
    and can(cow, 'Companions') is None and cow[everyone].view_channel is False)

# ------------------------------------------------------------------ F5 --
seats = places['seats']
yes('F5 #seats: every Jarl and faction Leader talks',
    all(can(seats, n) == 'talk' for n in B.SEATS))
yes('F5 #seats: the council talks',
    all(can(seats, n) == 'talk' for n in B.COUNCIL_ROLES))
yes('F5 #seats: a faction member, a Citizen and a Gamemaster get nothing',
    can(seats, 'Companions') is None and can(seats, 'Citizen of Whiterun') is None
    and can(seats, 'Gamemaster') is None)

# ------------------------------------------------------------------ F6 --
missing = [m for m in B.FACTION_MEMBERS if m not in lore]
yes('F6 lore/factions.md has every faction' + (': missing ' + ', '.join(missing) if missing else ''),
    not missing)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
