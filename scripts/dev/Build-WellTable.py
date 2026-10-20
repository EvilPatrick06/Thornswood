"""
Build-WellTable.py

Every well a person can fill a bottle at, read out of the load order (#1382).

WHY. Patrick, 12 Oct 2026: "every vanilla well object placed in towns, farms,
camps counts; well water is safe without boiling." The server cannot see a
well. It knows where somebody stands, so it needs where every well stands,
and that is a pass over placed references, the same pass Build-DoorTable.py
makes for doors.

WHICH OBJECTS ARE WELLS, and this is the one judgement in here. The bases are
named below by editor id, out of the STAT records of the five masters whose
editor id says Well, and each one left out says why. Nothing is matched by
pattern at run time: a mod adding a static called SomethingWell does not
become drinking water by accident.

WHAT IT WRITES. game\\data\\wells.json (the bases, every placement and where
it came from) and the WELLS line in game\\gamemode.js, which is what the
server reads: one row per placed well, [cellOrWorld, x, y, z].

Read only apart from those two files.

Usage:
    python scripts/dev/Build-WellTable.py --check
    python scripts/dev/Build-WellTable.py
"""

import argparse
import importlib.util
import io
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import own_plugins  # noqa: E402
_spec = importlib.util.spec_from_file_location('doortable', os.path.join(HERE, 'Build-DoorTable.py'))
dt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dt)

# The well bases, by editor id. Read out of Skyrim.esm and Dragonborn.esm on
# 12 Oct 2026: every STAT whose editor id says Well.
WELLS = {
    'GenericWell01': 'a plain stone well, towns and farms',
    'FarmWell01': 'a farm well',
    'FarmBWell01': 'a farm well, the second farm set',
    'FarmBWellEnt01': 'the head of the second farm set well',
    'ImpWell01': 'an Imperial well, Solitude and the Imperial camps',
    'ImpExtIceWell01': 'an Imperial well in the snow',
    'RTPlazaWell01': 'the well in a Markarth plaza',
    'RedoranWell01': 'the well in Raven Rock (Dragonborn)',
    'DLC2SkaalVilFarmWell01': 'the Skaal village well (Dragonborn)',
}
NOT_WELLS = {
    'WinterholdTowerWell01': 'a tower shaft of the College of Winterhold, no water',
    'WinterholdTowerWell02': 'the same tower shaft, no water',
    'RiftenRWHall1WayWell01': 'a Ratway hall piece, architecture, no water',
    'sc_lightwell01': 'a light well (Dawnguard), no water',
}

DELETED = 0x20
DISABLED = 0x800


def edid_of(pl, p, size, flags):
    for st, body in dt.subrecords(pl.data(p, size, flags)):
        if st == b'EDID':
            return body.rstrip(bytes([0])).decode('ascii', 'replace')
    return ''


def walk(pl, bases, seen_bases, placed):
    buf = pl.buf
    u32 = lambda i: struct.unpack_from('<I', buf, i)[0]

    def eat(start, end, cell, world, top):
        p = start
        while p + 24 <= end:
            tag = buf[p:p + 4]
            size = u32(p + 4)
            if tag == b'GRUP':
                gtype = u32(p + 12)
                kid, kw = cell, world
                if gtype == 1:
                    kw = pl.desc(u32(p + 8))
                if gtype == 6:
                    kid = pl.desc(u32(p + 8))
                eat(p + 24, p + size, kid, kw, top)
                p += size
                continue
            flags, fid = struct.unpack_from('<II', buf, p + 8)
            if top == b'STAT' and tag == b'STAT':
                e = edid_of(pl, p, size, flags)
                d = pl.desc(fid)
                if d and (e in WELLS or e in NOT_WELLS):
                    seen_bases[e] = d
                    if e in WELLS:
                        bases[d] = e
            elif tag == b'REFR' and cell:
                base = pos = None
                for st, body in dt.subrecords(pl.data(p, size, flags)):
                    if st == b'NAME' and len(body) >= 4:
                        base = pl.desc(struct.unpack_from('<I', body, 0)[0])
                    elif st == b'DATA' and len(body) >= 12:
                        pos = list(struct.unpack_from('<3f', body, 0))
                d = pl.desc(fid)
                if d and base in bases:
                    if (flags & (DELETED | DISABLED)) or not pos:
                        placed.pop(d, None)
                    else:
                        placed[d] = {'base': base, 'edid': bases[base], 'cell': cell,
                                     'world': world, 'pos': [round(v, 1) for v in pos],
                                     'from': pl.name}
                elif d in placed and base and base not in bases:
                    placed.pop(d, None)
            p += 24 + size

    p = 24 + pl.header
    while p + 24 <= len(buf):
        size = u32(p + 4)
        if buf[p:p + 4] != b'GRUP':
            break
        label = buf[p + 8:p + 12]
        if label in (b'STAT', b'CELL', b'WRLD'):
            eat(p + 24, p + size, None, None, label)
        p += size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=r'C:\Thornswood\Game\Data')
    ap.add_argument('--plugins', default=r'C:\Thornswood\Profile\Default\plugins.txt')
    ap.add_argument('--out', default=os.path.join(HERE, '..', '..', 'game', 'data', 'wells.json'))
    ap.add_argument('--gamemode', default=os.path.join(HERE, '..', '..', 'game', 'gamemode.js'))
    ap.add_argument('--check', action='store_true', help='say what it found, write nothing')
    args = ap.parse_args()

    order = list(dt.MASTERS)
    for line in io.open(args.plugins, encoding='utf-8', errors='replace'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('*'):
            line = line[1:]
        if line not in order:
            order.append(line)
    missing = [n for n in order if not os.path.isfile(own_plugins.plugin_path(args.data, n))]
    if missing:
        # Said, written into wells.json, and skipped: a plugin that is not on
        # this machine cannot be read, and the table says so rather than
        # pretending it was.
        print('NOTE. %d plugin(s) in plugins.txt are not in %s, skipped: %s'
              % (len(missing), args.data, ', '.join(missing)))
        order = [n for n in order if n not in missing]

    # Two passes, as the door table: the bases first, then the placements.
    bases, seen, placed = {}, {}, {}
    for name in order:
        pl = dt.Plugin(own_plugins.plugin_path(args.data, name), name)
        if pl.ok:
            walk(pl, bases, seen, {})
    lost = sorted(set(WELLS) - set(seen))
    if lost:
        print('STOP. well base(s) not in the load order: %s' % ', '.join(lost))
        return 1
    for name in order:
        pl = dt.Plugin(own_plugins.plugin_path(args.data, name), name)
        if pl.ok:
            walk(pl, bases, {}, placed)

    rows = []
    for d in sorted(placed):
        r = placed[d]
        where = r['world'] or r['cell']
        if where:
            rows.append([where] + r['pos'])
    byBase = {}
    for r in placed.values():
        byBase[r['edid']] = byBase.get(r['edid'], 0) + 1
    print('%d plugins; %d well bases; %d placed wells' % (len(order), len(bases), len(rows)))
    for e in sorted(byBase):
        print('  %-24s %d' % (e, byBase[e]))
    if args.check:
        return 0

    with io.open(args.out, 'w', encoding='utf-8', newline='\n') as f:
        json.dump({
            'builtBy': 'scripts\\dev\\Build-WellTable.py',
            'source': 'the STAT and placed REFR records of %d plugins in load order' % len(order),
            'skipped': missing,
            'rule': 'Patrick, 12 Oct 2026 (#1382): every vanilla well object placed in towns, '
                    'farms and camps counts, and well water is safe without boiling.',
            'wells': WELLS, 'notWells': NOT_WELLS,
            'bases': bases, 'byBase': byBase, 'placed': placed
        }, f, indent=1, sort_keys=True)
        f.write('\n')
    gm = io.open(args.gamemode, encoding='utf-8', newline='').read()
    line = 'const WELLS = ' + json.dumps({'items': rows}, separators=(',', ':')) + ';'
    if re.search(r'^const WELLS = .*;\r?$', gm, re.M):
        gm2 = re.sub(r'^const WELLS = .*;(\r?)$', lambda m: line + m.group(1), gm, count=1, flags=re.M)
    else:
        gm2 = re.sub(r'^(const WATERS = .*;)(\r?\n)', lambda m: m.group(1) + m.group(2) + line + m.group(2), gm, count=1, flags=re.M)
    if gm2 == gm and line not in gm:
        print('could not find where to put WELLS in gamemode.js')
        return 1
    io.open(args.gamemode, 'w', encoding='utf-8', newline='').write(gm2)
    print('wrote %s and the WELLS line' % args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
