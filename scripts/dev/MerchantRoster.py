"""Validate the authored guild roster before changing generated population rows."""
import re

ROLES = ('Smith', 'Woodworker', 'Tailor', 'Enchanter', 'Cook', 'Alchemist')
BOOK_HOLDS = {'whiterun': 'Whiterun', 'solitude': 'Haafingar', 'riften': 'the Rift',
              'markarth': 'the Reach', 'windhelm': 'Eastmarch', 'morthal': 'Hjaalmarch',
              'dawnstar': 'the Pale', 'winterhold': 'Winterhold', 'falkreath': 'Falkreath',
              'ravenrock': 'Solstheim'}


def static_identity(value):
    match = re.fullmatch(r'([0-9a-f]{1,6}):([^:/\\]+\.(?:esm|esp|esl))', value, re.I) if isinstance(value, str) else None
    return bool(match and int(match[1], 16) and match[1] == format(int(match[1], 16), 'x'))


def apply_roster(rows, policy):
    if (not isinstance(policy, dict) or set(policy) != {'version', 'worldMode', 'history', 'merchants'} or
            type(policy['version']) is not int or policy['version'] != 1 or policy['worldMode'] != 'existing'):
        raise ValueError('Guild retirement requires the existing-world roster policy')
    history, selected = policy['history'], policy['merchants']
    if not isinstance(history, list) or len(history) != 249 or not isinstance(selected, list) or len(selected) != 60:
        raise ValueError('Guild retirement must preserve 249 identities and retain 60 trades')
    by_ref = {}
    for row in rows:
        if row['ref'] in by_ref:
            raise ValueError('Duplicate source population identity')
        by_ref[row['ref']] = row
    historical = {}
    for pair in history:
        if not isinstance(pair, list) or len(pair) != 2 or not all(static_identity(value) for value in pair):
            raise ValueError('Invalid historical merchant identity')
        reference, base = pair
        source = by_ref.get(reference)
        if reference in historical or not source or source['base'] != base or source['role'] != 'trader':
            raise ValueError('Historical merchant identity disagrees with source records')
        historical[reference] = base
    if set(historical) != {row['ref'] for row in rows if row['role'] == 'trader'}:
        raise ValueError('Historical merchant manifest differs from the source trader census')
    assignments, coverage = {}, set()
    for merchant in selected:
        if (not isinstance(merchant, dict) or set(merchant) != {'reference', 'base', 'role', 'hold', 'bookHold'} or
                not all(isinstance(value, str) for value in merchant.values())):
            raise ValueError('Invalid guild role assignment')
        reference, role, hold = merchant['reference'], merchant['role'], merchant['bookHold']
        if not static_identity(reference) or not static_identity(merchant['base']):
            raise ValueError('Guild merchants require static source identities')
        source = by_ref.get(reference)
        if (reference in assignments or reference not in historical or not source['keep'] or
                merchant['base'] != historical[reference] or source['hold'] != merchant['hold'] or
                hold not in BOOK_HOLDS or BOOK_HOLDS[hold] != merchant['hold'] or role not in ROLES or
                (hold, role) in coverage):
            raise ValueError('Guild role, hold or retained identity disagrees with its source')
        assignments[reference] = role
        coverage.add((hold, role))
    if coverage != {(hold, role) for hold in BOOK_HOLDS for role in ROLES}:
        raise ValueError('Each hold requires exactly one of every guild trade')
    # Every identity and assignment is checked before any source row changes.
    for reference in historical:
        source = by_ref[reference]
        if reference in assignments:
            source['guildRole'] = assignments[reference]
            source['displayName'] = assignments[reference]
        else:
            source['keep'] = False
            source['reason'] = 'Guild roster retains one of each trade per hold'
    return [pair[:] for pair in history]
