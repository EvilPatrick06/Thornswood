#!/usr/bin/env python3
"""
New-ScriptPack.py

Makes the script pack: every Papyrus script a game PC's Data folder holds, in
one file the box can keep, so the content tools that read scripts read the
same ones there as on the PC. Issue #3105.

    python scripts/mods/New-ScriptPack.py --out <folder>
    python scripts/mods/New-ScriptPack.py --data D:\\Game\\Data --out <folder>

WHY. Build-CrimeTable.py reads every script of the load order (through
Audit-PapyrusEvents.py's script_index) to say which ones touch a bounty. The
scripts are in Skyrim - Misc.bsa, the Creation Club archives, the mods' own
archives and Data\\Scripts. Measured 21 Oct on One (#3105): about 15,700
.pex across 33 archives and 515 loose files, 15,496 of them the ones the game
resolves. The box holds none of those archives, so on 26 Oct the whole
rebuild there stopped at the crime table with 14,553 attached scripts
missing. Sending the archives whole would move about 2.5 GB, nearly all of it
meshes and textures, for 1,700 scripts outside Misc; this sends the scripts.

WHAT IT WRITES, into --out:
  papyrus-scripts.zip   archives/<archive>/<path in the archive> for every
                        .pex of every .bsa in the Data folder that holds one,
                        and loose/<name>.pex for each file of Data\\Scripts.
                        Every archive goes in, whatever the load order: the
                        pack is what the folder holds, and script_index picks
                        the winners by the load order of each run, the same
                        way it does from the archives themselves. Entries are
                        sorted and dated 1 Jan 1980, so the same Data folder
                        always makes the same bytes.
  papyrus-scripts.json  the record: the pack's size and sha256 and what it
                        holds. Copy it to records\\papyrus-scripts.json;
                        scripts\\mods\\Send-GameArchives.ps1 sends the pack only
                        when it is those bytes.

The pack holds Bethesda's and the mods' scripts, so it goes only to the
box's C:\\Thornswood-GameData, which is staff-only and served by nothing, like
the archives beside it. It is never committed.
"""
import argparse
import hashlib
import io
import json
import os
import struct
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'dev'))
import bsa  # noqa: E402

PACK = 'papyrus-scripts.zip'
RECORD = 'papyrus-scripts.json'
STAMP = (1980, 1, 1, 0, 0, 0)


def entries(data):
    """[(name in the pack, bytes)], sorted, and what each source gave."""
    out, archives, unreadable = [], {}, []
    for archive in sorted(os.listdir(data), key=str.lower):
        if not archive.lower().endswith('.bsa'):
            continue
        try:
            files = bsa.read(os.path.join(data, archive), 'scripts')
        except (OSError, ValueError, struct.error, zlib.error, IndexError) as exc:
            unreadable.append('%s: %s' % (archive, exc))
            continue
        pex = sorted(p for p in files if p.endswith('.pex'))
        if not pex:
            continue
        archives[archive] = len(pex)
        out += [('archives/%s/%s' % (archive, p), files[p]) for p in pex]
    loose = 0
    folder = os.path.join(data, 'Scripts')
    if os.path.isdir(folder):
        for f in sorted(os.listdir(folder), key=str.lower):
            full = os.path.join(folder, f)
            if f.lower().endswith('.pex') and os.path.isfile(full):
                with open(full, 'rb') as fh:
                    out.append(('loose/' + f, fh.read()))
                loose += 1
    return out, archives, loose, unreadable


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=r'C:\Thornswood\Game\Data', help="the game's Data folder")
    ap.add_argument('--out', required=True, help='the folder the pack and its record are written to')
    args = ap.parse_args()

    if not os.path.isfile(os.path.join(args.data, 'Skyrim - Misc.bsa')):
        print('STOP. %s holds no Skyrim - Misc.bsa, so it is not a game\'s Data folder. Nothing was written.' % args.data)
        return 1
    found, archives, loose, unreadable = entries(args.data)
    if unreadable:
        print('STOP. %d archive(s) could not be read, so the pack would lack their scripts. Nothing was written:' % len(unreadable))
        for u in unreadable:
            print('  ' + u)
        return 1
    os.makedirs(args.out, exist_ok=True)
    pack = os.path.join(args.out, PACK)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in found:
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)
    raw = buf.getvalue()
    with open(pack, 'wb') as fh:
        fh.write(raw)
    record = {
        '_note': 'The script pack scripts/mods/New-ScriptPack.py made from a game PC\'s Data folder (#3105). '
                 'scripts/mods/Send-GameArchives.ps1 sends it to the box\'s C:\\Thornswood-GameData only when it '
                 'is these bytes; scripts/mods/OnBox.ps1 links it into each run\'s data folder, where '
                 'scripts/dev/Audit-PapyrusEvents.py reads it in place of the archives the box does not hold. '
                 'Remake it when the collection adds, removes or changes an archive or loose script.',
        'file': PACK,
        'bytes': len(raw),
        'sha256': hashlib.sha256(raw).hexdigest(),
        'scripts': len(found),
        'archives': archives,
        'loose': loose,
    }
    with io.open(os.path.join(args.out, RECORD), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(json.dumps(record, indent=1, sort_keys=True) + '\n')
    print('%s: %d scripts, %d from %d archives and %d loose, %d bytes, sha256 %s'
          % (pack, len(found), len(found) - loose, len(archives), loose, len(raw), record['sha256']))
    print('The record is %s. Copy it to records\\papyrus-scripts.json.' % os.path.join(args.out, RECORD))
    return 0


if __name__ == '__main__':
    sys.exit(main())
