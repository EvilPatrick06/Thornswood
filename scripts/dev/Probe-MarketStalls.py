"""
Probe-MarketStalls.py (#3160, a measurement, not a builder)

Lists every base record whose editor id names a market stall, and every
placed reference of one over the load order, with where it stands. Read only.

    python scripts/dev/Probe-MarketStalls.py --data <the game's Data>
"""

import argparse
import importlib.util
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


wb = _module('build_woodworking_benches', os.path.join(HERE, 'Build-WoodworkingBenches.py'))

WANT = re.compile(r'stall|market|merchantstand|vendor|booth|kiosk', re.I)
BASES = {b'STAT', b'SCOL', b'MSTT', b'FURN', b'CONT', b'ACTI', b'IDLM'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    a = ap.parse_args()
    plugins = [wb.Plugin(p, n) for p, n in wb.load_order(a.data) if os.path.exists(p)]
    bases, cells, worlds = {}, {}, {}
    for pl in plugins:
        def visit(tag, p, size, flags, fid, world, cell, pl=pl):
            if tag not in BASES and tag not in (b'CELL', b'WRLD'):
                return
            ss = wb.subs(pl.body(p, size, flags))
            edid = next((b.rstrip(b'\0').decode('latin1') for t, b in ss if t == b'EDID'), '')
            k = pl.key(fid)
            if tag == b'CELL':
                interior = any(t == b'DATA' and len(b) >= 1 and b[0] & 1 for t, b in ss)
                cells[k] = (edid, world, interior)
            elif tag == b'WRLD':
                worlds[k] = edid
            elif WANT.search(edid):
                model = next((b.rstrip(b'\0').decode('latin1') for t, b in ss if t == b'MODL'), '')
                bases[k] = (tag.decode(), edid, model, pl.name)
        pl.walk(visit)
    print('BASES %d' % len(bases))
    for k, v in sorted(bases.items(), key=lambda kv: kv[1][1].lower()):
        print('  %x:%s %s %s %s (%s)' % (k[1], k[0], v[0], v[1], v[2], v[3]))
    refs = {}
    for pl in plugins:
        def visit(tag, p, size, flags, fid, world, cell, pl=pl):
            if tag != b'REFR':
                return
            ss = wb.subs(pl.body(p, size, flags))
            base = next((pl.key(struct.unpack_from('<I', b)[0]) for t, b in ss if t == b'NAME'), None)
            if base not in bases:
                return
            pos = next((struct.unpack_from('<6f', b) for t, b in ss if t == b'DATA' and len(b) >= 24), None)
            k = pl.key(fid)
            refs[k] = (base, pos, flags, world, cell, pl.name)
        pl.walk(visit, tops={b'WRLD', b'CELL'})
    print('REFS %d' % len(refs))
    rows = []
    for k, (base, pos, flags, world, cell, by) in refs.items():
        c = cells.get(cell, ('?', None, False))
        w = worlds.get(world or c[1], '') if not c[2] else ''
        rows.append((w or '(interior)', c[0], bases[base][1], k, pos, flags, by))
    near = {}
    if refs:
        allbases = {}
        for pl in plugins:
            def vb(tag, p, size, flags, fid, world, cell, pl=pl):
                if tag in (b'CONT', b'ACTI', b'FURN', b'DOOR'):
                    ss = wb.subs(pl.body(p, size, flags))
                    allbases[pl.key(fid)] = (tag.decode(), next((b.rstrip(b'\0').decode('latin1') for t, b in ss if t == b'EDID'), ''))
            pl.walk(vb)
        spots = [(k, v[3] or v[4], v[1]) for k, v in refs.items() if v[1]]
        for pl in plugins:
            def vr(tag, p, size, flags, fid, world, cell, pl=pl):
                if tag != b'REFR':
                    return
                ss = wb.subs(pl.body(p, size, flags))
                base = next((pl.key(struct.unpack_from('<I', b)[0]) for t, b in ss if t == b'NAME'), None)
                if base not in allbases:
                    return
                pos = next((struct.unpack_from('<6f', b) for t, b in ss if t == b'DATA' and len(b) >= 24), None)
                if not pos:
                    return
                w = world or cell
                for k, sw, sp in spots:
                    if sw == w and (pos[0] - sp[0]) ** 2 + (pos[1] - sp[1]) ** 2 + (pos[2] - sp[2]) ** 2 <= 400 ** 2:
                        near.setdefault(k, []).append('%s %s %x:%s' % (allbases[base][0], allbases[base][1], fid & 0xFFFFFF, pl.name))
            pl.walk(vr, tops={b'WRLD', b'CELL'})
    for w, c, b, k, pos, flags, by in sorted(rows, key=lambda r: (r[0], r[1], r[2])):
        print('  %-18s %-28s %-36s %x:%s pos=%s flags=%x by=%s' % (
            w, c, b, k[1], k[0], ','.join('%.0f' % v for v in (pos or ())[:3]) + ' rz=%.2f' % (pos[5] if pos else 0), flags, by))
        for x in near.get(k, [])[:12]:
            print('      near: ' + x)


if __name__ == '__main__':
    main()
