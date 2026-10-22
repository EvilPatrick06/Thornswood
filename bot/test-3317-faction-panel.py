"""
test-3317-faction-panel.py

A faction's Leader gives and takes its member role from a bot panel (#3317,
Patrick, 22 Oct, page card q-3317-faction-member-give, A). The same shape as
a Jarl's office panel (#2551):

  P1 the panel is a persistent view of Add member and Remove member, and
     setup_hook registers it; it lives in #seats and is found again by its
     own buttons
  P2 the member role the bot gives is the one Build-Discord.py makes, for
     every faction in factions.json
  L1 a press by somebody who leads no faction is refused, only to them
  L2 the Companions Leader's Add asks who, and the pick gives Companions,
     with the reason in Discord's audit log; it is not said to staff
  L3 Remove offers who holds it, and the pick takes it back
  L4 the Companions Leader cannot give Thalmor by any button
  L5 while two accounts hold the Companions Leader role, neither does anything
  L6 a bot is given nothing, and somebody already holding it is told so
  L7 somebody leading two factions is asked which first

The builder and bot.py are imported for real, the builder under another name
so its __main__ block never runs. Read only. Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.11 or newer, #2276)
import asyncio
import importlib.util
import inspect
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


try:
    import discord  # noqa: E402
except ImportError:
    print('SKIP  discord.py is not installed here, so the builder and the bot cannot be imported')
    print('')
    print('0 passed, 0 failed')
    sys.exit(0)

spec = importlib.util.spec_from_file_location(
    'build_discord_3317_fp', os.path.join(HERE, 'Build-Discord.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

import bot  # noqa: E402

bot.log = lambda *a: None
STAFF_SAID = []


async def staff_say(text):
    STAFF_SAID.append(text)

bot.report_say = staff_say

# ------------------------------------------------------------------ P1 --
ids = [i.custom_id for i in bot.FactionPanel().children]
yes('P1 the panel is two buttons, Add member and Remove member',
    ids == ['thornswood:faction:add', 'thornswood:faction:remove']
    and [i.label for i in bot.FactionPanel().children] == ['Add member', 'Remove member'])
hook = inspect.getsource(bot.Thornswood.setup_hook)
yes('P1 setup_hook registers it, so the buttons outlive a restart',
    'add_view(FactionPanel())' in hook)
src = inspect.getsource(bot.ensure_faction_panel)
yes('P1 it is in #seats, found again by its own buttons, posted at start',
    bot.FACTION_PANEL_CHANNEL == ['seats'] and 'seats' in dict(
        (s['name'], s) for s in dict(B.PLAN)['Factions'])
    and "startswith('thornswood:faction:')" in src
    and 'await ensure_faction_panel(g)' in inspect.getsource(bot.on_ready))

# ------------------------------------------------------------------ P2 --
yes('P2 the bot gives each faction the member role the builder makes, by the same short name',
    [bot.faction_member_role(f) for f in bot.faction_names()] == list(B.FACTION_MEMBERS)
    and [bot.faction_leader_role(f) for f in bot.faction_names()] == list(B.FACTION_LEADERS)
    and bot.FACTION_SHORT == B.FACTION_SHORT)


# ------------------------------------------------------- a pretend server --
class Role(object):
    def __init__(self, guild, name, rid):
        self.guild = guild
        self.name = name
        self.id = rid

    @property
    def members(self):
        return [m for m in self.guild.members if self in m.roles]

    def __lt__(self, other):
        return True


class Member(object):
    def __init__(self, guild, mid, name, roles, is_bot=False):
        self.guild = guild
        self.id = mid
        self.display_name = name
        self.roles = roles
        self.bot = is_bot
        self.changes = []

    async def add_roles(self, role, reason=None):
        self.roles.append(role)
        self.changes.append(('add', role.name, reason))

    async def remove_roles(self, role, reason=None):
        self.roles = [r for r in self.roles if r is not role]
        self.changes.append(('remove', role.name, reason))


class Guild(object):
    def __init__(self):
        self.roles = []
        self.members = []
        self.me = type('Me', (), {'guild_permissions': discord.Permissions(manage_roles=True),
                                  'top_role': None})()

    def role(self, name):
        r = Role(self, name, 100 + len(self.roles))
        self.roles.append(r)
        return r

    def member(self, name, roles, is_bot=False):
        m = Member(self, 1000 + len(self.members), name, roles, is_bot)
        self.members.append(m)
        return m

    def get_member(self, mid):
        for m in self.members:
            if m.id == mid:
                return m
        return None


class Response(object):
    def __init__(self):
        self.said = []
        self.views = []

    async def send_message(self, text, view=None, ephemeral=False):
        self.said.append((text, ephemeral))
        if view is not None:
            self.views.append(view)


class Interaction(object):
    def __init__(self, guild, user):
        self.guild = guild
        self.user = user
        self.response = Response()


def world():
    g = Guild()
    roles = {}
    for n in ['Companions Leader', 'Companions', 'Thalmor Leader', 'Thalmor', 'Member']:
        roles[n] = g.role(n)
    g.me.top_role = Role(g, 'Thornswood Bot', 999)
    people = {
        'kodlak': g.member('Kodlak', [roles['Companions Leader'], roles['Member']]),
        'aela': g.member('Aela', [roles['Member']]),
        'nobody': g.member('Nobody', [roles['Member']]),
        'botty': g.member('Some Bot', [], is_bot=True),
    }
    return g, roles, people


async def press(guild, who, add):
    i = Interaction(guild, who)
    await bot.faction_press(i, add)
    return i


async def main():
    g, roles, p = world()

    i = await press(g, p['nobody'], True)
    yes('L1 somebody who leads no faction is refused, and only they see it',
        len(i.response.said) == 1 and i.response.said[0][1] is True
        and 'Only the Leader of a faction' in i.response.said[0][0] and not i.response.views)

    i = await press(g, p['kodlak'], True)
    view = i.response.views[0] if i.response.views else None
    yes('L2 the Companions Leader\'s Add asks who joins The Companions, only to them',
        view is not None and i.response.said[0] == ('Who joins The Companions?', True)
        and isinstance(view.children[0], discord.ui.UserSelect))
    pick = Interaction(g, p['kodlak'])
    STAFF_SAID[:] = []
    await bot.faction_change(pick, 'The Companions', p['aela'], True)
    yes('L2 the pick gives Aela the Companions role, with the reason in the audit log',
        roles['Companions'] in p['aela'].roles
        and p['aela'].changes[-1] == ('add', 'Companions',
                                      'Given by Kodlak, Leader of The Companions, on the faction panel'))
    yes('L2 it says so to the Leader, and nothing to staff',
        pick.response.said[0][0] == 'Aela holds the Companions role now.' and STAFF_SAID == [])

    again = Interaction(g, p['kodlak'])
    await bot.faction_change(again, 'The Companions', p['aela'], True)
    yes('L6 giving it again changes nothing, and says so',
        'already holds' in again.response.said[0][0] and len(p['aela'].changes) == 1)
    robot = Interaction(g, p['kodlak'])
    await bot.faction_change(robot, 'The Companions', p['botty'], True)
    yes('L6 and a bot is given nothing',
        robot.response.said[0][0] == 'A bot joins no faction.' and not p['botty'].changes)

    i = await press(g, p['kodlak'], False)
    view = i.response.views[0] if i.response.views else None
    yes('L3 Remove offers who holds the role',
        [o.value for o in view.children[0].options] == [str(p['aela'].id)] if view else False)
    take = Interaction(g, p['kodlak'])
    await bot.faction_change(take, 'The Companions', p['aela'], False)
    yes('L3 and the pick takes it back, with the reason',
        roles['Companions'] not in p['aela'].roles
        and p['aela'].changes[-1] == ('remove', 'Companions',
                                      'Taken by Kodlak, Leader of The Companions, on the faction panel'))

    other = Interaction(g, p['kodlak'])
    await bot.faction_change(other, 'Thalmor Remnant', p['aela'], True)
    yes('L4 the Companions Leader gives nothing of the Thalmor',
        other.response.said[0][0] == 'Only the Leader of Thalmor Remnant gives its member role.'
        and roles['Thalmor'] not in p['aela'].roles)

    p['aela'].roles.append(roles['Companions Leader'])
    twice = await press(g, p['kodlak'], True)
    yes('L5 while two accounts hold the Companions Leader role, the panel does nothing and says why',
        'Two accounts hold the Companions Leader role' in twice.response.said[0][0]
        and not twice.response.views)
    late = Interaction(g, p['kodlak'])
    await bot.faction_change(late, 'The Companions', p['nobody'], True)
    yes('L5 even for a pick made before the second one was given',
        'neither acts as its Leader' in late.response.said[0][0]
        and roles['Companions'] not in p['nobody'].roles)
    p['aela'].roles.remove(roles['Companions Leader'])

    both = g.member('Two Seats', [roles['Companions Leader'], roles['Thalmor Leader']])
    pick = await press(g, both, True)
    yes('L7 somebody leading two factions is asked which first, in factions.json order',
        'Which one?' in pick.response.said[0][0] and pick.response.views
        and [o.value for o in pick.response.views[0].children[0].options]
        == ['Thalmor Remnant', 'The Companions'])

asyncio.run(main())

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
