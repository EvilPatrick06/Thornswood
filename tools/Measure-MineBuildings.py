"""
Measure-MineBuildings.py

Lists every building that holds a placed ore vein, and every building a lock
would shut a vein behind.

WHY

Entry 325 on the To Do List. Two of Patrick's rulings meet at a mine and nobody
has put them side by side yet:

  17 September, the mining design agreed in Discord: "Nobody owns a mine."
  21 September, the property system: "every building in the game is
  claimable, shops and halls and palaces included, so people can lock doors
  and own shops."

Today the second one wins without anybody having chosen it: /claim takes any
building BUILDING_BY_DOOR knows, and a claimed building can be locked. Which of
the two holds is his to say, and this script says nothing about it. What he
needs in front of him to say it is which buildings are actually mines, and a
name is not that. Miner's Barracks has "Mine" in it and no vein, and a cave
called something else can be full of iron. So this answers it from the
plugins, the way the door table was built.

WHAT A MINE IS HERE. A building holding at least one placed reference whose
base is in ORES_BY_BASE. That table is exactly what mineOre lets a person work,
so this counts what the server mines and nothing the server does not.

ON THE WAY IN. A lock keeps people out of a building, and a mine whose veins
are two rooms down is shut just as well by a lock on the first room. So for
every building with a vein this also names the buildings that every road from
open ground to it goes through. The roads come from tools\\doors.json, the
table BUILDING_BY_DOOR was generated from, so a building here is the same
building /claim would take.

WHAT IT READS. The plugins in load order, the five masters and then
plugins.txt, last one wins, which is the rule Build-DoorTable.py uses and whose
plugin reader this borrows rather than copies. ORES_BY_BASE, BUILDING_BY_DOOR
and BUILDING_NAME out of tools\\gamemode.js. tools\\doors.json.

WHAT IT WRITES. Nothing, unless --out names a file, and then that one file. It
changes no rule and touches neither the gamemode nor the claim.

Usage:
    python tools/Measure-MineBuildings.py
    python tools/Measure-MineBuildings.py --out tools/mine-buildings.json
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
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# Build-DoorTable.py already reads a plugin: the header, the master list, a form
# id as <hex>:<plugin>, compressed records, localised names. A second copy of
# that here would be a second place for it to be wrong. Its name has a hyphen
# in it, so it is loaded by path rather than imported.
_spec = importlib.util.spec_from_file_location('door_table', os.path.join(HERE, 'Build-DoorTable.py'))
dt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dt)

# Record flags. A deleted reference is gone from the world. An initially
# disabled one is placed but not there until something enables it, so it is
# counted and said, rather than hidden or passed off as a vein anybody can see.
DELETED = 0x20
DISABLED = 0x800

MINE_WORD = re.compile(r'\bMines?\b')


def walk(pl, ores, cells, worlds, veins, removed):
    """Every CELL, every WRLD's editor id, and every placed ore vein."""
    buf = pl.buf
    u32 = lambda i: struct.unpack_from('<I', buf, i)[0]

    def eat(start, end, cell, world):
        p = start
        while p + 24 <= end:
            tag = buf[p:p + 4]
            size = u32(p + 4)
            if tag == b'GRUP':
                gtype = u32(p + 12)
                kcell, kworld = cell, world
                # Type 1 is a worldspace's children and its label is the
                # worldspace. Type 6 is a cell's children and its label is the
                # cell.
                if gtype == 1:
                    kworld = pl.desc(u32(p + 8))
                elif gtype == 6:
                    kcell = pl.desc(u32(p + 8))
                eat(p + 24, p + size, kcell, kworld)
                p += size
                continue
            flags, fid = struct.unpack_from('<II', buf, p + 8)
            if tag == b'WRLD':
                d = pl.desc(fid)
                if d:
                    for st, body in dt.subrecords(pl.data(p, size, flags)):
                        if st == b'EDID':
                            worlds[d] = body.rstrip(bytes([0])).decode('ascii', 'replace')
                            break
            elif tag == b'CELL':
                d = pl.desc(fid)
                if d:
                    name, full, interior = '', '', False
                    for st, body in dt.subrecords(pl.data(p, size, flags)):
                        if st == b'EDID':
                            name = body.rstrip(bytes([0])).decode('ascii', 'replace')
                        elif st == b'FULL':
                            full = pl.text(body)
                        elif st == b'DATA' and len(body) >= 1:
                            interior = bool(body[0] & dt.CELL_INTERIOR)
                    row = {'edid': name, 'interior': interior}
                    if full:
                        row['name'] = full
                    if world and not interior:
                        row['world'] = world
                    cells[d] = row
            elif tag == b'REFR' and cell:
                d = pl.desc(fid)
                if d:
                    base = None
                    if not (flags & DELETED):
                        for st, body in dt.subrecords(pl.data(p, size, flags)):
                            if st == b'NAME' and len(body) >= 4:
                                base = pl.desc(struct.unpack_from('<I', body, 0)[0])
                                break
                    if base in ores:
                        veins[d] = {'base': base, 'cell': cell,
                                    'disabled': bool(flags & DISABLED)}
                        removed.discard(d)
                    elif d in veins:
                        # A later plugin deleted this vein or made it something
                        # else, and the last plugin is the one the game believes.
                        del veins[d]
                        removed.add(d)
            p += 24 + size

    p = 24 + pl.header
    while p + 24 <= len(buf):
        size = struct.unpack_from('<I', buf, p + 4)[0]
        if buf[p:p + 4] != b'GRUP':
            break
        if buf[p + 8:p + 12] in (b'CELL', b'WRLD'):
            eat(p + 24, p + size, None, None)
        p += size


def generated(text, name):
    """One of the gamemode's generated `const NAME = {...};` lines, as a dict."""
    m = re.search(r'^const ' + name + r' = (\{.*\});[ \t\r]*$', text, re.M)
    return json.loads(m.group(1)) if m else None


def ore_table(text):
    """ORES_BY_BASE out of its generated block, as a dict, or None."""
    a = text.find('// ==== ORES_BY_BASE, generated ====')
    b = text.find('// ==== end ORES_BY_BASE ====')
    if a < 0 or b < a:
        return None
    block = text[a:b]
    s = block.find('{')
    e = block.rfind('}')
    if s < 0 or e < s:
        return None
    return json.loads(block[s:e + 1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=r'C:\Thornswood\Game\Data')
    ap.add_argument('--plugins', default=r'C:\Thornswood\Profile\Default\plugins.txt')
    ap.add_argument('--gamemode', default=os.path.join(HERE, 'gamemode.js'))
    ap.add_argument('--doors', default=os.path.join(HERE, 'doors.json'))
    ap.add_argument('--out', default=None, help='write the measurement as JSON to this file')
    args = ap.parse_args()

    text = io.open(args.gamemode, encoding='utf-8', newline='').read()
    ores = ore_table(text)
    by_door = generated(text, 'BUILDING_BY_DOOR')
    names = generated(text, 'BUILDING_NAME')
    # A table that is not there would make every answer below "no mines", which
    # reads exactly like a world with no mines in it. So it stops instead.
    for label, t in (('ORES_BY_BASE', ores), ('BUILDING_BY_DOOR', by_door),
                     ('BUILDING_NAME', names)):
        if not t:
            print('STOP. %s is not in %s, so there is nothing to measure against.'
                  % (label, args.gamemode))
            return 1
    doors = json.load(io.open(args.doors, encoding='utf-8'))
    claimable = set(by_door.values())

    order = list(dt.MASTERS)
    for line in io.open(args.plugins, encoding='utf-8', errors='replace'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('*'):
            line = line[1:]
        if line not in order:
            order.append(line)
    missing = [n for n in order if not os.path.isfile(os.path.join(args.data, n))]
    if missing:
        print('STOP. %d plugin(s) are not in %s: %s'
              % (len(missing), args.data, ', '.join(missing[:6])))
        return 1

    print('The load order')
    print('  %d plugins, the five masters then %s' % (len(order), args.plugins))

    cells, worlds, veins, removed = {}, {}, {}, set()
    failed = 0
    for name in order:
        pl = dt.Plugin(os.path.join(args.data, name), name)
        if not pl.ok:
            continue
        # Only a vein's cell needs a name a person would know, and only when the
        # gamemode's BUILDING_NAME does not already have one. The string tables
        # are still read up front, because which cells hold veins is not known
        # until the walk is over.
        if pl.localised:
            pl.strings = dt.bsa.load_strings(args.data, name)
        walk(pl, ores, cells, worlds, veins, removed)
        failed += pl.failed

    def called(c):
        if c in names:
            return names[c]
        row = cells.get(c, {})
        return row.get('name') or row.get('edid') or c

    def interior(c):
        # A cell nothing read is taken as open ground, the same call
        # Build-DoorTable.py makes, so an unknown cell never makes a building
        # look like the only road in.
        row = cells.get(c) or doors['cells'].get(c)
        return bool(row and row.get('interior'))

    in_building, no_door, open_ground = {}, {}, {}
    disabled = 0
    for d, v in veins.items():
        c = v['cell']
        if v['disabled']:
            disabled += 1
        if not interior(c):
            w = cells.get(c, {}).get('world')
            w = worlds.get(w, w) or 'an unnamed worldspace'
            open_ground[w] = open_ground.get(w, 0) + 1
        elif c in claimable:
            in_building.setdefault(c, []).append(v)
        else:
            no_door.setdefault(c, []).append(v)

    # The roads. Both halves of a door pair name each other, so every link is
    # recorded both ways and it does not matter which half was read first.
    placed = doors['doors']
    links = {}
    for d, r in placed.items():
        other = placed.get(r.get('to'))
        if other:
            links.setdefault(r['cell'], set()).add(other['cell'])
            links.setdefault(other['cell'], set()).add(r['cell'])

    def reaches_open(start, without):
        seen, todo = set([start]), [start]
        while todo:
            c = todo.pop()
            if not interior(c):
                return True
            for n in links.get(c, ()):
                if n != without and n not in seen:
                    seen.add(n)
                    todo.append(n)
        return False

    def indoors_from(start):
        seen, todo = set([start]), [start]
        while todo:
            c = todo.pop()
            for n in links.get(c, ()):
                if n not in seen and interior(n):
                    seen.add(n)
                    todo.append(n)
        return seen

    way_in, shuts, sealed = {}, {}, []
    for v in in_building:
        if not reaches_open(v, None):
            sealed.append(v)
            continue
        on = [b for b in indoors_from(v)
              if b != v and b in claimable and not reaches_open(v, b)]
        way_in[v] = sorted(on, key=called)
        for b in on:
            shuts.setdefault(b, []).append(v)

    has_vein = set(in_building) | set(no_door)
    no_vein_mines = {b: n for b, n in names.items()
                     if MINE_WORD.search(n) and b not in has_vein and b not in shuts}

    total = len(veins)
    inside = sum(len(v) for v in in_building.values())
    nowhere = sum(len(v) for v in no_door.values())
    outside = sum(open_ground.values())

    print('')
    print('Ore veins')
    print('  %d vein base(s) in ORES_BY_BASE' % len(ores))
    print('  %s placed vein reference(s), last plugin wins' % format(total, ','))
    print('  %d of them initially disabled, %d removed by a later plugin'
          % (disabled, len(removed)))
    print('  %s on open ground: %s' % (format(outside, ','), ', '.join(
        '%s %d' % (w, n) for w, n in sorted(open_ground.items(), key=lambda x: (-x[1], x[0])))))
    print('  %s inside a building somebody can /claim, across %d building(s)'
          % (format(inside, ','), len(in_building)))
    print('  %s inside an interior no door leads into, across %d cell(s), so nobody can claim it'
          % (format(nowhere, ','), len(no_door)))
    if failed:
        print('  %d compressed record(s) would not inflate, so this is incomplete' % failed)

    def ore_line(rows):
        count = {}
        for r in rows:
            n = ores[r['base']]['name']
            count[n] = count.get(n, 0) + 1
        return count, ', '.join('%s %d' % (n, k) for n, k in
                                sorted(count.items(), key=lambda x: (-x[1], x[0])))

    print('')
    print('Buildings that hold a vein, which /claim takes and a lock shuts today')
    for b in sorted(in_building, key=called):
        rows = in_building[b]
        _, line = ore_line(rows)
        print('  %-30s %3d  %s' % (called(b), len(rows), line))
        if way_in.get(b):
            print('  %-30s      reached only through %s'
                  % ('', ', '.join(called(x) for x in way_in[b])))
    if sealed:
        print('')
        print('Holding a vein with no door road to open ground, so reached some other way')
        for b in sorted(sealed, key=called):
            print('  %s' % called(b))

    # The ones that hold a vein themselves are in the list above already, with
    # the road written under the building they shut. These are the buildings a
    # rule about mines would miss if it only looked for veins.
    bare = [b for b in shuts if b not in has_vein]
    print('')
    print('Buildings with no vein of their own that a lock would shut a vein behind')
    if not bare:
        print('  none')
    for b in sorted(bare, key=called):
        print('  %-30s shuts %s' % (called(b), ', '.join(called(x) for x in sorted(shuts[b], key=called))))

    # Printed with the cell as well as the name, because an editor's test cell
    # can carry the same name as the real building it was copied from.
    print('')
    print('Interiors holding a vein that no door leads into')
    if not no_door:
        print('  none')
    for c in sorted(no_door, key=called):
        print('  %-30s %3d  %s' % (called(c), len(no_door[c]), c))

    print('')
    print('Buildings called a mine that hold no vein and shut none')
    if not no_vein_mines:
        print('  none')
    for b in sorted(no_vein_mines, key=lambda x: no_vein_mines[x]):
        print('  %s' % no_vein_mines[b])

    if not args.out:
        print('')
        print('  No --out, so nothing was written.')
        return 0

    def building_row(b):
        rows = in_building[b]
        count, _ = ore_line(rows)
        row = {'name': called(b), 'veins': len(rows), 'ores': count,
               'onTheWayIn': way_in.get(b, [])}
        off = sum(1 for r in rows if r['disabled'])
        if off:
            row['disabled'] = off
        if b in sealed:
            row['noDoorRoad'] = True
        return row

    payload = {
        'builtBy': 'tools/Measure-MineBuildings.py',
        'readFrom': '%d plugins, the five masters then %s' % (len(order), args.plugins),
        'whatAMineIs': 'a building holding at least one placed reference whose base is in '
                       'ORES_BY_BASE, which is exactly what mineOre lets a person work. A '
                       'building is what BUILDING_BY_DOOR says, the one /claim takes.',
        'counts': {'veinBases': len(ores), 'placed': total, 'disabled': disabled,
                   'removedByLaterPlugin': len(removed), 'openGround': outside,
                   'inBuildings': inside, 'buildings': len(in_building),
                   'noDoor': nowhere, 'failedToInflate': failed},
        'buildings': dict((b, building_row(b)) for b in in_building),
        'onTheWayIn': dict((b, {'name': called(b), 'shuts': sorted(shuts[b]),
                                'holdsVein': b in has_vein}) for b in shuts),
        'noDoor': dict((c, {'name': called(c), 'veins': len(no_door[c])}) for c in no_door),
        'openGround': open_ground,
        'calledAMineWithNoVein': no_vein_mines,
    }
    io.open(args.out, 'w', encoding='utf-8', newline='\n').write(
        json.dumps(payload, indent=1, sort_keys=True) + '\n')
    print('')
    print('  wrote %s (%s bytes)' % (args.out, format(os.path.getsize(args.out), ',')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
