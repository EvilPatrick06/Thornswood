"""
List-CellRefs.py

Reads only. Says what stands in an interior cell over the load order, and
which base records of some kind it has, so a placement can be measured from
the plugins instead of typed from the game.

    python scripts/dev/List-CellRefs.py --data <Data> --cell 1380e:Skyrim.esm --cell 13810:Skyrim.esm
    python scripts/dev/List-CellRefs.py --data <Data> --bases "(?i)desk"
    pwsh scripts/mods/Run-OnBox.ps1 scripts/dev/List-CellRefs.py --data '{data}' --cell 1380e:Skyrim.esm

WHY (#1387). Patrick, 22 October 2026, A: College study is taken at a study
desk in the College halls. Where a desk can stand in each hall, and which
desk mesh the game has, are in the plugins, not in this repository: this is
the measurement the desk's placement starts from. The load order is
game/data/last-plugin.json's, read the way Build-StationSites.py reads it
(own_plugins.plugin_path: Thornswood's own plugins from game/content).

What it prints, one JSON object a line:
  {"cell": ..., "ref": ..., "base": ..., "type": ..., "edid": ..., "model": ...,
   "bounds": [...], "pos": [...], "rot": [...], "scale": ..., "by": ...}
for every reference in each --cell, the winning record of each (a deleted or
disabled one says so), and
  {"baseRecord": ..., "type": ..., "edid": ..., "model": ..., "bounds": [...], "by": ...}
for every base record whose EDID matches --bases. Nothing is written.
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
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import own_plugins  # noqa: E402

spec = importlib.util.spec_from_file_location('build_woodworking_benches', os.path.join(HERE, 'Build-WoodworkingBenches.py'))
wb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wb)

DELETED, DISABLED = 0x20, 0x800


def key_of(desc):
    fid, name = desc.split(':', 1)
    return (name.lower(), int(fid, 16))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=os.environ.get('THORNSWOOD_DATA') or r'C:\Thornswood\Game\Data')
    ap.add_argument('--cell', action='append', default=[], help='an interior cell, as <hex id>:<plugin>')
    ap.add_argument('--bases', default='', help='a regular expression over base records\' EDID')
    args = ap.parse_args()
    if not args.cell and not args.bases:
        print('Name a --cell or --bases.')
        return 2

    lo = json.load(io.open(os.path.join(ROOT, 'game', 'data', 'last-plugin.json'), encoding='utf-8'))['loadOrder']
    order = [(own_plugins.plugin_path(args.data, n), n) for n in lo]
    missing = [n for p, n in order if not os.path.isfile(p)]
    if missing:
        print('STOP. %d plugin(s) of the load order are not there: %s' % (len(missing), ', '.join(missing[:6])))
        return 1
    plugins = [wb.Plugin(p, n) for p, n in order]
    world = wb.World(plugins)

    cells = {key_of(c): c for c in args.cell}
    for k, c in cells.items():
        if k not in world.cells:
            print('STOP. %s is not a cell in the load order' % c)
            return 1
    refs = {}
    for pl in plugins:
        def visit(tag, p, size, flags, fid, w, cell, pl=pl):
            if tag not in (b'REFR', b'ACHR') or cell not in cells:
                return
            k = pl.key(fid)
            base, pos, scale = None, None, 1.0
            for t, b in wb.subs(pl.body(p, size, flags)):
                if t == b'NAME':
                    base = pl.key(struct.unpack_from('<I', b)[0])
                elif t == b'DATA' and len(b) >= 24:
                    pos = struct.unpack_from('<6f', b)
                elif t == b'XSCL':
                    scale = struct.unpack_from('<f', b)[0]
            refs[k] = dict(cell=cells[cell], base=base, pos=pos, scale=scale, flags=flags, by=pl.name)
        pl.walk(visit, tops={b'CELL'})

    for k in sorted(refs, key=lambda x: (refs[x]['cell'], x)):
        r = refs[k]
        b = world.bases.get(r['base']) if r['base'] else None
        out = {'cell': r['cell'], 'ref': world.desc(k), 'base': world.desc(r['base']) if r['base'] else None,
               'type': b[0] if b else None, 'edid': b[1] if b else None, 'model': b[5] if b else None,
               'bounds': list(b[2]) if b and b[2] else None,
               'pos': [round(v, 1) for v in r['pos'][:3]] if r['pos'] else None,
               'rot': [round(v * 57.29578, 2) for v in r['pos'][3:]] if r['pos'] else None,
               'scale': round(r['scale'], 3), 'by': r['by']}
        if r['flags'] & DELETED:
            out['deleted'] = True
        if r['flags'] & DISABLED:
            out['disabled'] = True
        print(json.dumps(out))

    if args.bases:
        pat = re.compile(args.bases)
        for k in sorted(world.bases, key=lambda x: world.bases[x][1].lower()):
            b = world.bases[k]
            if pat.search(b[1]):
                print(json.dumps({'baseRecord': world.desc(k), 'type': b[0], 'edid': b[1], 'model': b[5],
                                  'bounds': list(b[2]) if b[2] else None, 'by': b[4]}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
