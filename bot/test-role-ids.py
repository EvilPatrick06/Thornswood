"""
test-role-ids.py

Discord permission roles are matched by ID when a token is all digits, and by
name (case-insensitive) otherwise. STAFF_ROLES, CREATOR_ROLES, MEMBER_ROLE and
LIVE_SMOKE_ADMIN_ROLES all share that contract so a rename does not silently
break tickets, holds or Live smoke (#1355).

Defaults stay the current role names so older harnesses that read STAFF,
CREATOR, MEMBER_ROLE and LIVE_SMOKE_ADMIN still pass with an unmigrated
bot.env.json.

The real bot module is imported. _role_tokens and _role_hit are driven with
small stand-ins; no Discord, no token, no network.

Read only. Never connects to anything.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# Force the documented defaults so this file does not inherit a VPS env.
for _k in ('STAFF_ROLES', 'CREATOR_ROLES', 'MEMBER_ROLE', 'LIVE_SMOKE_ADMIN_ROLES'):
    os.environ.pop(_k, None)

# bot.py refuses to load without one, and never uses it unless client.run is
# called, which nothing here does.
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')

import bot  # noqa: E402

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


class Role(object):
    """Enough of a discord.Role for _role_hit: an id and a name."""

    def __init__(self, rid, name):
        self.id = rid
        self.name = name


# --------------------------------------------------------------- helpers --

ids, names = bot._role_tokens(['111', 'Owner', ' 222 ', 'Gamemaster', '', '  '])
yes('_role_tokens puts all-digit tokens into ids as ints',
    ids == {111, 222})
yes('_role_tokens puts every other token into names, lowercased',
    names == {'owner', 'gamemaster'})

yes('_role_hit matches a role by id when the token was digits',
    bot._role_hit(Role(111, 'RenamedAway'), {111}, set()))
yes('_role_hit does not match a different id',
    not bot._role_hit(Role(999, 'RenamedAway'), {111}, set()))
yes('_role_hit matches a role by name, case-insensitive',
    bot._role_hit(Role(1, 'OwNeR'), set(), {'owner'}))
yes('_role_hit does not match a different name',
    not bot._role_hit(Role(1, 'Moderator'), set(), {'owner'}))
yes('_role_hit accepts either id or name on the same call',
    bot._role_hit(Role(111, 'Nope'), {111}, {'owner'})
    and bot._role_hit(Role(9, 'Owner'), {111}, {'owner'}))

# ---------------------------------------------------------- staff / creator --

yes('STAFF defaults stay the current names (old harnesses)',
    set(bot.STAFF_NAMES) == {'owner', 'gamemaster', 'dev', 'loremaster', 'moderator'}
    and bot.STAFF_IDS == set()
    and set(bot.STAFF) == {'owner', 'gamemaster', 'dev', 'loremaster', 'moderator'})
yes('CREATOR defaults stay Content Creator (old harnesses)',
    bot.CREATOR_NAMES == {'content creator'}
    and bot.CREATOR_IDS == set()
    and bot.CREATOR == ['content creator'])

staff_role = Role(42, 'Owner')
renamed = Role(42, 'WasOwner')
yes('STAFF_IDS/NAMES via _role_hit: default name still hits Owner',
    bot._role_hit(staff_role, bot.STAFF_IDS, bot.STAFF_NAMES))
yes('STAFF via _role_tokens digits: id hits after a rename',
    (lambda i, n: bot._role_hit(renamed, i, n))(
        *bot._role_tokens(['42', 'Gamemaster'])))

creator_role = Role(7, 'Content Creator')
yes('CREATOR_IDS/NAMES via _role_hit: default name still hits Content Creator',
    bot._role_hit(creator_role, bot.CREATOR_IDS, bot.CREATOR_NAMES))
yes('CREATOR via _role_tokens digits: id hits a renamed creator role',
    (lambda i, n: bot._role_hit(Role(7, 'Social'), i, n))(
        *bot._role_tokens(['7'])))

# -------------------------------------------------------------- MEMBER_ROLE --

yes('MEMBER_ROLE default stays member (old harnesses)',
    bot.MEMBER_ROLE == 'member')
member_ids, member_names = bot._role_tokens([bot.MEMBER_ROLE])
yes('MEMBER_ROLE name token matches Member case-insensitively',
    bot._role_hit(Role(1, 'MeMbEr'), member_ids, member_names)
    and member_ids == set() and member_names == {'member'})
mid_ids, mid_names = bot._role_tokens(['555'])
yes('MEMBER_ROLE digit token matches role.id (rename-safe)',
    bot._role_hit(Role(555, 'WasMember'), mid_ids, mid_names)
    and mid_ids == {555} and mid_names == set())

# ------------------------------------------------- LIVE_SMOKE_ADMIN_ROLES --

yes('LIVE_SMOKE_ADMIN_ROLES defaults stay Owner,Dev,Lead Gamemaster,Lead GM',
    bot.LIVE_SMOKE_ADMIN_NAMES == ['Owner', 'Dev', 'Lead Gamemaster', 'Lead GM']
    and set(bot.LIVE_SMOKE_ADMIN) == {
        'owner', 'dev', 'lead gamemaster', 'lead gm'})
ls_ids, ls_names = bot._role_tokens(bot.LIVE_SMOKE_ADMIN_NAMES)
yes('LIVE_SMOKE_ADMIN name tokens match Lead GM / Lead Gamemaster',
    bot._role_hit(Role(1, 'Lead GM'), ls_ids, ls_names)
    and bot._role_hit(Role(2, 'lead gamemaster'), ls_ids, ls_names)
    and ls_ids == set())
ls_id_ids, ls_id_names = bot._role_tokens(['999001', 'Dev'])
yes('LIVE_SMOKE_ADMIN digit token matches role.id; name token still matches',
    bot._role_hit(Role(999001, 'WasLead'), ls_id_ids, ls_id_names)
    and bot._role_hit(Role(3, 'Dev'), ls_id_ids, ls_id_names)
    and ls_id_ids == {999001} and ls_id_names == {'dev'})

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)