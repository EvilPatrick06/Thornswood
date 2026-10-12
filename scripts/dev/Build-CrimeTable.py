"""
Build-CrimeTable.py

Reads every faction in the load order and writes down each one in which
killing or striking one of its members puts a bounty on whoever did it.

WHY

Patrick, 11 October, on #502: "there should be no bounties at all added when
killing NPCs". Nothing Thornswood wrote adds a bounty: no line of the
gamemode, the plugins or the fork's server calls ModCrimeGold or SetCrimeGold.
The bounty is Skyrim's own crime system, running in each person's game. When
somebody kills or strikes an actor whose crime faction tracks crime, the game
adds the faction's murder or assault gold to that faction's bounty. Most hold
crime factions take those amounts from the game settings iCrimeGoldMurder and
iCrimeGoldAttack ("Use Defaults" on the faction), but not all: measured on
12 October, CrimeFactionReach carries its own 1000 and 40. So zeroing the two
settings would leave Markarth's bounty in place, and the cause has to be
answered on each faction: the ignore murder and ignore assault flags, which
tell the game that killing or striking a member is not a crime against that
faction. game/plugins/thornswood-front.js sets them on every faction this
lists, when a game is loaded.

WHAT IT READS. Nothing but the plugins: the five masters, then the plugins
plugins.txt marks active (a line starting with *), in load order, last one
wins. A line without * is a plugin that is installed and switched off, which
the game does not load, so it is not read either.

WHAT IT WRITES. game\\data\\crime-factions.json, every listed faction with its
flags, its amounts and the plugin whose record won, and the
KILL_CRIME_FACTIONS block in game\\plugins\\thornswood-front.js, the form ids
the plugin flags.

Read only apart from those two files.

Usage:
    python scripts/dev/Build-CrimeTable.py --check
    python scripts/dev/Build-CrimeTable.py
"""

import argparse
import importlib.util
import io
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# Build-DoorTable.py already reads a plugin: the header, the master list, a
# form id as <hex>:<plugin>, compressed records. Its name has a hyphen in it,
# so it is loaded by path rather than imported.
_spec = importlib.util.spec_from_file_location('door_table', os.path.join(HERE, 'Build-DoorTable.py'))
dt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dt)

# FACT DATA flags, as the record and SKSE's SetFactionFlag both number them.
TRACK_CRIME = 0x40
IGNORE_MURDER = 0x80
IGNORE_ASSAULT = 0x100
USE_DEFAULTS = 0x1000

# The game settings a faction with Use Defaults takes its amounts from, and
# what Skyrim.esm ships them at, for a load order that never overrides them.
GMST_MURDER = 'iCrimeGoldMurder'
GMST_ASSAULT = 'iCrimeGoldAttack'


def active_order(plugins_txt):
    order = list(dt.MASTERS)
    for line in io.open(plugins_txt, encoding='utf-8', errors='replace'):
        line = line.strip()
        if not line.startswith('*'):
            continue
        line = line[1:]
        if line not in order:
            order.append(line)
    return order


def top_groups(pl, want):
    """Each record in the top groups named in want, as (tag, flags, fid, offset, size)."""
    buf = pl.buf
    u32 = lambda i: struct.unpack_from('<I', buf, i)[0]
    p = 24 + pl.header
    while p + 24 <= len(buf):
        size = u32(p + 4)
        if buf[p:p + 4] != b'GRUP':
            break
        if buf[p + 8:p + 12] in want:
            q = p + 24
            while q + 24 <= p + size:
                tag = buf[q:q + 4]
                rs = u32(q + 4)
                if tag == b'GRUP':
                    q += rs
                    continue
                flags, fid = struct.unpack_from('<II', buf, q + 8)
                yield tag, flags, fid, q, rs
                q += 24 + rs
        p += size


def read(data, order):
    factions, settings = {}, {}
    for name in order:
        pl = dt.Plugin(os.path.join(data, name), name)
        if not pl.ok:
            continue
        for tag, flags, fid, q, rs in top_groups(pl, (b'FACT', b'GMST')):
            pairs = dt.subrecords(pl.data(q, rs, flags))
            if tag == b'GMST':
                edid, value = '', None
                for st, body in pairs:
                    if st == b'EDID':
                        edid = body.rstrip(bytes([0])).decode('ascii', 'replace')
                    elif st == b'DATA' and len(body) >= 4:
                        value = struct.unpack_from('<i', body, 0)[0]
                if edid in (GMST_MURDER, GMST_ASSAULT) and value is not None:
                    settings[edid] = {'value': value, 'from': name}
                continue
            d = pl.desc(fid)
            if not d:
                continue
            row = {'from': name, 'edid': '', 'flags': 0, 'murder': 0, 'assault': 0}
            for st, body in pairs:
                if st == b'EDID':
                    row['edid'] = body.rstrip(bytes([0])).decode('ascii', 'replace')
                elif st == b'DATA' and len(body) >= 4:
                    row['flags'] = struct.unpack_from('<I', body, 0)[0]
                elif st == b'CRVA' and len(body) >= 6:
                    # arrest, attack on sight, then murder and assault as two
                    # 16 bit amounts.
                    row['murder'], row['assault'] = struct.unpack_from('<HH', body, 2)
            factions[d] = row
    return factions, settings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=r'C:\Thornswood\Game\Data')
    ap.add_argument('--plugins', default=r'C:\Thornswood\Profile\Default\plugins.txt')
    ap.add_argument('--out', default=os.path.join(HERE, '..', '..', 'game', 'data', 'crime-factions.json'))
    ap.add_argument('--front', default=os.path.join(HERE, '..', '..', 'game', 'plugins', 'thornswood-front.js'))
    ap.add_argument('--check', action='store_true', help='say what it found, write nothing')
    args = ap.parse_args()

    order = active_order(args.plugins)
    missing = [n for n in order if not os.path.isfile(os.path.join(args.data, n))]
    if missing:
        print('STOP. %d active plugin(s) are not in %s: %s'
              % (len(missing), args.data, ', '.join(missing[:6])))
        return 1
    print('The load order')
    print('  %d active plugins, the five masters then %s' % (len(order), args.plugins))

    factions, settings = read(args.data, order)
    murder_default = settings.get(GMST_MURDER, {}).get('value', 1000)
    assault_default = settings.get(GMST_ASSAULT, {}).get('value', 40)
    print('')
    print('The game settings a faction on Use Defaults takes')
    print('  %s %d, %s %d' % (GMST_MURDER, murder_default, GMST_ASSAULT, assault_default))

    listed = {}
    tracking = 0
    for d, r in factions.items():
        f = r['flags']
        if not (f & TRACK_CRIME):
            continue
        tracking += 1
        defaults = bool(f & USE_DEFAULTS)
        murder = murder_default if defaults else r['murder']
        assault = assault_default if defaults else r['assault']
        costs = ((murder > 0 and not (f & IGNORE_MURDER)) or
                 (assault > 0 and not (f & IGNORE_ASSAULT)))
        if not costs:
            continue
        listed[d] = {'edid': r['edid'], 'from': r['from'], 'flags': '0x%x' % f,
                     'useDefaults': defaults, 'murder': murder, 'assault': assault}

    print('')
    print('Factions')
    print('  %d faction record(s), %d of them track crime' % (len(factions), tracking))
    print('  %d of those put a bounty on a kill or a blow:' % len(listed))
    for d in sorted(listed, key=lambda k: listed[k]['edid'].lower()):
        r = listed[d]
        print('    %-28s %-24s murder %5d, assault %4d, %s'
              % (r['edid'], d, r['murder'], r['assault'],
                 'Use Defaults' if r['useDefaults'] else 'its own amounts'))

    if args.check:
        print('')
        print('  --check, so nothing was written.')
        return 0

    payload = {
        'builtBy': 'scripts/dev/Build-CrimeTable.py',
        'readFrom': '%d active plugins, the five masters then %s' % (len(order), args.plugins),
        'whatIsListed': 'every faction that tracks crime and in which killing or striking a member '
                        'adds a bounty: murder or assault gold above 0 that the faction does not '
                        'ignore, the game settings standing in for a faction on Use Defaults.',
        'settings': {GMST_MURDER: murder_default, GMST_ASSAULT: assault_default},
        'factions': listed,
    }
    io.open(args.out, 'w', encoding='utf-8', newline='\n').write(
        json.dumps(payload, indent=1, sort_keys=True) + '\n')
    print('')
    print('  wrote %s' % args.out)

    rows = []
    for d in sorted(listed, key=lambda k: listed[k]['edid'].lower()):
        local, plugin = d.split(':', 1)
        rows.append('    [0x%s, %s, %s],' % (local, json.dumps(plugin), json.dumps(listed[d]['edid'])))
    text = io.open(args.front, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in text else '\n'
    mark = 'KILL_CRIME_FACTIONS'
    a = text.find('// ==== %s, generated ====' % mark)
    b = text.find('// ==== end %s ====' % mark)
    if a < 0 or b < 0 or b < a:
        print('  no %s block in the front plugin, so it was not written' % mark)
        return 1
    lines = ['// ==== %s, generated ====' % mark,
             '  // One row a faction: its form id in its plugin, the plugin, its editor id.',
             '  // Generated by scripts\\dev\\Build-CrimeTable.py; do not hand edit.',
             '  const KILL_CRIME_FACTIONS = ['] + rows + ['  ];']
    text = text[:a] + nl.join(lines) + nl + '  ' + text[b:]
    io.open(args.front, 'w', encoding='utf-8', newline='').write(text)
    print('  wrote %s into the front plugin' % mark)
    return 0


if __name__ == '__main__':
    sys.exit(main())
