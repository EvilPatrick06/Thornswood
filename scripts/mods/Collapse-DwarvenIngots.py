"""
Collapse-DwarvenIngots.py

#613: six Skyrim.esm RecipeIngotDwarvenScrap* smelter recipes all make
Dwarven Metal Ingot and all show in the craft menu. Keep one scrap path
(RecipeIngotDwarvenScrapPlateMetalLarge / Large Dwemer Plate Metal -> 3
ingots). Hide the other five by overriding them in Thornswood-Content.esp
with no workbench keyword (BNAM), so the smelter menu lists one row.

Does not invent sale prices. Player-run economy.

  python scripts/mods/Collapse-DwarvenIngots.py
  python scripts/mods/Collapse-DwarvenIngots.py --check
"""
from __future__ import print_function

import argparse
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
ESP = os.path.join(ROOT, 'game', 'content', 'Thornswood-Content.esp')
SKYRIM = os.environ.get('SKYRIM_ESM') or os.path.join('C:\\', 'Thornswood', 'Game', 'Data', 'Skyrim.esm')

# Keeper stays as Skyrim ships it. These five are the duplicates cut-items
# already named: one row per ingot name, Skyrim.esm first by form id, keep
# 10dd28, cut the rest.
HIDE = [
    0x0010FBD9,  # RecipeIngotDwarvenScrapPlateMetalSmall
    0x0010DD2D,  # RecipeIngotDwarvenScrapLarge03
    0x0010DD2C,  # RecipeIngotDwarvenScrapLarge02
    0x0010DD2B,  # RecipeIngotDwarvenScrapLarge
    0x0010DD2A,  # RecipeIngotDwarvenScrapBent
]
KEEP = 0x0010DD28  # RecipeIngotDwarvenScrapPlateMetalLarge


def cnto(base, count):
    return struct.pack('<II', base, count)


class Rec(object):
    def __init__(self, tag, flags, fid, extra, data):
        self.tag, self.flags, self.fid, self.extra, self.data = tag, flags, fid, extra, data

    @property
    def compressed(self):
        return bool(self.flags & 0x00040000)

    def bytes(self):
        return self.tag + struct.pack('<III', len(self.data), self.flags, self.fid) + self.extra + self.data

    def editor_id(self):
        for t, b in subrecords(plain(self)):
            if t == b'EDID':
                return b.split(b'\x00')[0].decode('ascii', 'replace')
        return ''


class Grup(object):
    def __init__(self, label, kids):
        self.label, self.kids = label, kids

    def bytes(self):
        body = b''.join(k.bytes() for k in self.kids)
        return b'GRUP' + struct.pack('<I', 24 + len(body)) + self.label + body


def subrecords(data):
    out = []
    i = 0
    while i + 6 <= len(data):
        tag = data[i:i + 4]
        size = struct.unpack_from('<H', data, i + 4)[0]
        i += 6
        out.append((tag, data[i:i + size]))
        i += size
    return out


def pack_subrecords(pairs):
    return b''.join(t + struct.pack('<H', len(b)) + b for t, b in pairs)


def plain(rec):
    return zlib.decompress(rec.data[4:]) if rec.compressed else rec.data


def parse(buf, start, end):
    kids = []
    i = start
    while i < end:
        tag = buf[i:i + 4]
        if tag == b'GRUP':
            size = struct.unpack_from('<I', buf, i + 4)[0]
            label = buf[i + 8:i + 24]
            kids.append(Grup(label, parse(buf, i + 24, i + size)))
            i += size
        else:
            size, flags, fid = struct.unpack_from('<III', buf, i + 4)
            extra = buf[i + 16:i + 24]
            data = buf[i + 24:i + 24 + size]
            kids.append(Rec(tag, flags, fid, extra, data))
            i += 24 + size
    return kids


def every_record(kids):
    for k in kids:
        if isinstance(k, Grup):
            for r in every_record(k.kids):
                yield r
        else:
            yield k


def ensure_top_group(tree, tag):
    for k in tree:
        if isinstance(k, Grup) and k.label[:4] == tag:
            return k
    sample = next(k for k in tree if isinstance(k, Grup))
    stamp = sample.label[12:16] if len(sample.label) >= 16 else b'\x00' * 4
    g = Grup(tag + b'\x00' * 8 + stamp, [])
    tree.append(g)
    return g


def find_cobj(skyrim_buf, fid):
    """Locate one uncompressed COBJ by form id in Skyrim.esm."""
    needle = b'COBJ' + struct.pack('<I', 0)  # size varies; search fid instead
    # Walk records naively via string search for the form id after COBJ header
    # Pattern: COBJ + size(4) + flags(4) + fid(4)
    target = struct.pack('<I', fid)
    start = 0
    while True:
        p = skyrim_buf.find(b'COBJ', start)
        if p < 0:
            return None
        if p + 16 <= len(skyrim_buf) and skyrim_buf[p + 12:p + 16] == target:
            size, flags, got = struct.unpack_from('<III', skyrim_buf, p + 4)
            if got != fid:
                start = p + 4
                continue
            extra = skyrim_buf[p + 16:p + 24]
            data = skyrim_buf[p + 24:p + 24 + size]
            return Rec(b'COBJ', flags, fid, extra, data)
        start = p + 4


def hide_workbench(rec):
    """Same recipe bytes without BNAM, so no smelter (or any bench) lists it."""
    data = plain(rec)
    if pack_subrecords(subrecords(data)) != data and not rec.compressed:
        # still try
        pass
    pairs = [(t, b) for t, b in subrecords(data) if t != b'BNAM']
    if len(pairs) == len(list(subrecords(data))):
        raise SystemExit('STOP. 0x%07X has no BNAM to drop.' % rec.fid)
    out = Rec(b'COBJ', 0, rec.fid, rec.extra, pack_subrecords(pairs))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--esp', default=ESP)
    ap.add_argument('--skyrim', default=SKYRIM)
    args = ap.parse_args()

    if not os.path.isfile(args.esp):
        print('STOP. no plugin at', args.esp)
        return 1
    if not os.path.isfile(args.skyrim):
        print('STOP. no Skyrim.esm at', args.skyrim)
        return 1

    raw = open(args.esp, 'rb').read()
    skyrim = open(args.skyrim, 'rb').read()
    header_size = struct.unpack_from('<I', raw, 4)[0]
    head = bytearray(raw[:24 + header_size])
    tree = parse(raw, 24 + header_size, len(raw))
    records = list(every_record(tree))
    by_fid = dict((r.fid, r) for r in records)

    print('Collapse Dwarven Metal Ingot scrap recipes (#613)')
    print('  keep  0x%07X RecipeIngotDwarvenScrapPlateMetalLarge' % KEEP)
    print('  hide  %d duplicate RecipeIngotDwarvenScrap* rows' % len(HIDE))

    built = []
    already = []
    for fid in HIDE:
        if fid in by_fid:
            existing = by_fid[fid]
            pairs = subrecords(plain(existing))
            if not any(t == b'BNAM' for t, _ in pairs):
                already.append(fid)
                print('  already hidden 0x%07X %s' % (fid, existing.editor_id()))
                continue
            # Re-hide if somehow BNAM returned
        src = find_cobj(skyrim, fid)
        if src is None:
            print('STOP. Skyrim.esm has no COBJ 0x%07X' % fid)
            return 1
        hidden = hide_workbench(src)
        print('  override 0x%07X %s  (drop BNAM)' % (fid, src.editor_id()))
        built.append(hidden)

    # Keeper must still have BNAM in Skyrim and must not be overridden here.
    if KEEP in by_fid:
        print('STOP. keeper 0x%07X is already overridden in Content.esp; leave it to Skyrim.' % KEEP)
        return 1
    keep_src = find_cobj(skyrim, KEEP)
    if keep_src is None:
        print('STOP. keeper missing from Skyrim.esm')
        return 1
    if not any(t == b'BNAM' for t, _ in subrecords(plain(keep_src))):
        print('STOP. keeper has no BNAM in Skyrim.esm')
        return 1
    print('  keeper ok 0x%07X %s' % (KEEP, keep_src.editor_id()))

    if args.check:
        print('  --check, nothing written. would add', len(built), 'overrides; already', len(already))
        return 0

    if not built:
        print('  Everything already collapsed. Nothing was written.')
        return 0

    # Replace existing overrides of the same ids if we are rewriting them.
    replace = set(r.fid for r in built)
    def strip(kids):
        out = []
        for k in kids:
            if isinstance(k, Grup):
                k.kids = strip(k.kids)
                if k.kids or True:
                    out.append(k)
            elif k.fid in replace:
                continue
            else:
                out.append(k)
        return out
    tree = strip(tree)
    kept = [r for r in every_record(tree)]
    for r in built:
        ensure_top_group(tree, b'COBJ').kids.append(r)

    hedr = head.find(b'HEDR')
    if hedr < 0:
        print('STOP. no HEDR')
        return 1
    struct.pack_into('<i', head, hedr + 6 + 4, len(kept) + len(built))
    out = bytes(head) + b''.join(k.bytes() for k in tree)

    after = list(every_record(parse(out, 24 + header_size, len(out))))
    for r in built:
        got = next((x for x in after if x.fid == r.fid), None)
        if got is None:
            print('STOP. 0x%07X missing after write' % r.fid)
            return 1
        if any(t == b'BNAM' for t, _ in subrecords(plain(got))):
            print('STOP. 0x%07X still has BNAM' % r.fid)
            return 1
    if any(x.fid == KEEP for x in after):
        print('STOP. keeper was written into Content.esp')
        return 1

    open(args.esp, 'wb').write(out)
    print('  wrote', format(len(raw), ','), '->', format(len(out), ','), 'bytes')
    print('  THIS IS A SHIPPED FILE. Size changed; clients redownload.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
