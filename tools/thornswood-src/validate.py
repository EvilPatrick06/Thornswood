#!/usr/bin/env python3
"""Structural check on the emitted plugin: every GRUP size exact, every record
header consistent, every form id in range, no orphaned bytes."""
import struct, sys, collections
sys.path.insert(0, '/home/claude/tw')
from index import fields, zstr, HDR

P = '/mnt/user-data/outputs/thornswood/Thornswood-Content.esp'
raw = open(P, 'rb').read()
problems = []
counts = collections.Counter()
nmasters = None

def walk(s, e, depth, path):
    off = s
    while off < e:
        if off + HDR > e:
            problems.append('%s: %d trailing bytes at %d' % (path, e - off, off))
            return
        rt = raw[off:off + 4]
        if rt == b'GRUP':
            gs, label, gtype = struct.unpack_from('<IIi', raw, off + 4)
            if gs < HDR:
                problems.append('%s: GRUP at %d has size %d' % (path, off, gs))
                return
            if off + gs > e:
                problems.append('%s: GRUP at %d overruns its parent by %d' % (path, off, off + gs - e))
                return
            walk(off + HDR, off + gs, depth + 1, path + '/GRUP%d' % gtype)
            off += gs
            continue
        ds, fl, fid = struct.unpack_from('<III', raw, off + 4)
        if off + HDR + ds > e:
            problems.append('%s: %s %08x overruns its group' % (path, rt.decode(), fid))
            return
        counts[rt.decode()] += 1
        idx = fid >> 24
        if nmasters is not None and idx > nmasters:
            problems.append('%s %08x: master index %d but only %d masters + self'
                            % (rt.decode(), fid, idx, nmasters))
        # every field length must add up to the record body exactly
        if not (fl & 0x00040000):
            body = raw[off + HDR:off + HDR + ds]
            o = 0
            xxxx = None
            while o + 6 <= len(body):
                t = body[o:o + 4]
                sz = struct.unpack_from('<H', body, o + 4)[0]
                o += 6
                if t == b'XXXX':
                    xxxx = struct.unpack_from('<I', body, o)[0]
                    o += sz
                    continue
                if xxxx is not None:
                    sz, xxxx = xxxx, None
                if not (t[:1].isalpha() or t[:1].isdigit()):
                    problems.append('%s %08x: field tag %r is not a tag' % (rt.decode(), fid, t))
                    break
                o += sz
            if o != len(body):
                problems.append('%s %08x: fields sum to %d, body is %d'
                                % (rt.decode(), fid, o, len(body)))
        off += HDR + ds

# masters, for the index range check
d0, f0, _ = struct.unpack_from('<III', raw, 4)
nmasters = sum(1 for t, _ in fields(raw[HDR:HDR + d0]) if t == b'MAST')

walk(0, len(raw), 0, '')

hedr = None
for t, v in fields(raw[HDR:HDR + d0]):
    if t == b'HEDR':
        hedr = struct.unpack('<fiI', v[:12])

total = sum(counts.values())
if hedr and hedr[1] != total - 1:
    problems.append('HEDR says %d records, the file holds %d besides TES4' % (hedr[1], total - 1))

print('%s' % P)
print('  %d bytes, %d records, %d masters' % (len(raw), total, nmasters))
print('  HEDR ver=%.2f nrec=%d nextobj=%06x' % hedr)
print('  ' + ', '.join('%s %d' % kv for kv in counts.most_common()))
if problems:
    print('\n%d PROBLEM(S):' % len(problems))
    for p in problems[:30]:
        print('   ' + p)
    sys.exit(1)
print('\n  structure is clean')

# and the books specifically
import json
own = {}
def collect(s, e):
    off = s
    while off + HDR <= e:
        rt = raw[off:off + 4]
        if rt == b'GRUP':
            gs = struct.unpack_from('<I', raw, off + 4)[0]
            if gs < HDR: return
            collect(off + HDR, min(off + gs, e)); off += gs; continue
        ds, fl, fid = struct.unpack_from('<III', raw, off + 4)
        if rt == b'BOOK':
            b = {t: v for t, v in fields(raw[off + HDR:off + HDR + ds])}
            own[fid] = b
        off += HDR + ds
collect(0, len(raw))

bad = []
for fid, b in sorted(own.items()):
    for need in (b'EDID', b'FULL', b'MODL', b'MODT', b'DESC', b'DATA', b'INAM'):
        if need not in b:
            bad.append('%08x missing %s' % (fid, need.decode()))
    if b'DATA' in b and len(b[b'DATA']) != 16:
        bad.append('%08x DATA is %d bytes' % (fid, len(b[b'DATA'])))
    if b'FULL' in b and (len(b[b'FULL']) < 2 or b[b'FULL'][-1] != 0):
        bad.append('%08x FULL is not a terminated string' % fid)
print('  %d BOOK records, all with a name, a mesh and a text' % len(own)
      if not bad else '  BOOK PROBLEMS: ' + '; '.join(bad))
sys.exit(1 if bad else 0)
