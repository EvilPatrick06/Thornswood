"""Vortex state.v2 folders built as LevelDB from rows a harness names.

    python vortex-state-rows.py <root> <spec.json>

The spec maps a case name to {"table": [{"key": k, "value": json}, ...],
"log": [...]}, each value the JSON text Vortex stores. A log row whose value
is null is a deletion, the way Vortex removes a key. Each case becomes
<root>/<case>/Vortex/state.v2, so <root>/<case> is the APPDATA a harness points
at. Table rows go into a compressed table, the way state is left after
compaction; log rows go into the write-ahead log after it, the way Vortex
writes a change before compaction. A case with no table rows gets the
Thornswood profile there, as a real state.v2 holds one.

The writer is vortex-profile-state.py's, the one the reader's own fixtures use,
so a harness builds what launcher/app/VortexProfileState.cs reads. Running it
also writes that file's profile fixtures under <root>, the way
vortex-collection-state.py does; a case may not take one of their names, and
a case folder may hold anything already except a state.v2.
"""
import json
import pathlib
import runpy
import struct
import sys

tools = runpy.run_path(str(pathlib.Path(__file__).with_name('vortex-profile-state.py')))
fixture, lp, fragmented_log = (tools[n] for n in ('fixture', 'lp', 'fragmented_log'))
root = pathlib.Path(sys.argv[1])
spec = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8-sig'))


def table_rows(rows, sequence=10):
    return [(row['key'].encode() + struct.pack('<Q', ((sequence + i) << 8) | 1), row['value'].encode())
            for i, row in enumerate(rows)]


def put_or_delete(row):
    if row['value'] is None:
        return b'\0' + lp(row['key'].encode())
    return b'\1' + lp(row['key'].encode()) + lp(row['value'].encode())


def log(rows, sequence=100):
    return fragmented_log([struct.pack('<QI', sequence + i, 1) + put_or_delete(row)
                           for i, row in enumerate(rows)])


for name, case in spec.items():
    if (root / name / 'Vortex' / 'state.v2').exists():
        sys.exit('case ' + name + ' already has a state.v2 under ' + str(root))
    table = case.get('table') or []
    rows = case.get('log') or []
    fixture(root, name, table_rows(table) if table else None, log(rows) if rows else None)
