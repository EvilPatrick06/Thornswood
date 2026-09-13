#!/usr/bin/env python3
"""
patch_esp.py - give the Keizaal skill manuals a name, a mesh and a text, and add
the character-creation books.

Keizaal shipped its fifteen manuals as bare shells: EDID, an empty OBND, an empty
DESC and a DATA of all zeros. No FULL, so no name. No MODL, so no mesh. In game
they are nameless, invisible, weightless objects, which is fine for a mod that
only ever counted them in a script and fatal for a gamemode that expects somebody
to find one and read it.

Every donor field here (OBND, MODL, MODT, YNAM, INAM, the keyword) is lifted from
a vanilla record that uses the same mesh, so the art and its texture hashes agree.
FULL and DESC are written as plain cp1252 strings: this plugin is not localised,
so a copied lstring id would render as four bytes of garbage.
"""
import struct, sys, collections
sys.path.insert(0, '/home/claude/tw')
from index import index, fields, zstr, HDR
import content as C

SRC = '/mnt/user-data/uploads/SkyrimTogether/Game/Data/Thornswood-Content.esp'
OUT = '/mnt/user-data/outputs/thornswood/Thornswood-Content.esp'

raw = open(SRC, 'rb').read()
root, recs = index(raw)


def field(tag, value):
    return tag + struct.pack('<H', len(value)) + value


def zs(s):
    return s.encode('cp1252', 'replace') + b'\0'


def book_body(edid, title, text, mesh, value, weight, teaches=0xFFFFFFFF):
    m = C.MESH[mesh]
    out = b''
    out += field(b'EDID', zs(edid))
    out += field(b'OBND', m['obnd'])
    out += field(b'FULL', zs(title))
    out += field(b'MODL', zs(m['modl']))
    out += field(b'MODT', m['modt'])
    out += field(b'DESC', zs(text))
    if m['ynam'] is not None:
        out += field(b'YNAM', struct.pack('<I', m['ynam']))
    out += field(b'KSIZ', struct.pack('<I', 1))
    out += field(b'KWDA', struct.pack('<I', C.KWDA_VENDORITEMBOOK))
    # flags, type, unused, teaches, value, weight
    out += field(b'DATA', struct.pack('<BBHIIf', 0, 0, 0, teaches, value, weight))
    out += field(b'INAM', struct.pack('<I', m['inam']))
    return out


# The last eight bytes of a record header are version control info and the form
# version. Take them from a record this plugin already ships so every record in
# the file agrees about which game wrote it.
sample = next(r for r in recs.values() if r.type == b'BOOK')
HDR_TAIL = raw[sample.start + 16:sample.start + HDR]


def record(rtype, fid, body):
    return rtype + struct.pack('<III', len(body), 0, fid) + HDR_TAIL + body


# ---------------------------------------------------------------- manuals ----
rewritten = {}
for fid, (title, track, tier) in C.MANUAL_TITLES.items():
    if fid not in recs:
        raise SystemExit('manual %08x is not in this plugin' % fid)
    body = C.MANUAL_BODY[(track, tier)]
    text = ('<p align="center"><font size="34">' + title + '</font><br><br>'
            '<font size="22">' + C.TIER_WORD[tier] + ' ' + C.TRACK_WORD[track] +
            '</font></p><br><br>[pagebreak]<br><br>' + body)
    edid = None
    for t, v in fields(recs[fid].body):
        if t == b'EDID':
            edid = zstr(v)
            break
    rewritten[fid] = book_body(edid, title, text, 'book3',
                               value=10 * tier, weight=1.0)

# ---------------------------------------------------------------- new books --
new_books = []

new_books.append((C.WELCOME_FID, book_body(
    'ThornswoodWelcome', 'Before You Go',
    '<p align="center"><font size="34">Before You Go</font></p><br><br>[pagebreak]<br><br>'
    + C.WELCOME_TEXT, 'book6', value=0, weight=0.0)))

new_books.append((C.ALCHEMY_NOVICE_FID, book_body(
    'ThornswoodAlchemyNovice', 'Four Effects, One Mouth',
    '<p align="center"><font size="34">Four Effects, One Mouth</font><br><br>'
    '<font size="22">Novice alchemy</font></p><br><br>[pagebreak]<br><br>'
    + C.MANUAL_BODY[('alchemy', 1)], 'book3', value=10, weight=1.0)))

for key, fid, title, blurb in C.CLASSES:
    text = ('<p align="center"><font size="30">' + title + '</font></p><br><br>'
            + blurb + '<br><br><font size="18">Reading this writ settles the '
            'matter. The other five will burn.</font>')
    new_books.append((fid, book_body('ThornswoodWrit' + key.capitalize(),
                                     title, text, 'note3', 0, 0.0)))

for key, fid, title, town, blurb in C.DESTS:
    text = ('<p align="center"><font size="30">' + title + '</font></p><br><br>'
            + blurb + '<br><br><font size="18">Read this and you go. The other '
            'passages will burn.</font>')
    new_books.append((fid, book_body('ThornswoodPassage' + key.capitalize(),
                                     title, text, 'note2', 0, 0.0)))

# ---------------------------------------------------------------- menus -----
def message_body(edid, desc, buttons):
    out = b''
    out += field(b'EDID', zs(edid))
    out += field(b'DESC', zs(desc))
    out += field(b'INAM', struct.pack('<I', 0))
    out += field(b'DNAM', struct.pack('<I', 1))      # 1 = message box, not a toast
    for b in buttons:
        out += field(b'ITXT', zs(b))
    return out


new_messages = [
    (C.TRADE_MENU_FID, message_body(C.TRADE_MENU['edid'], C.TRADE_MENU['desc'],
                                    C.TRADE_MENU['buttons'])),
    (C.TOWN_MENU_FID,  message_body(C.TOWN_MENU['edid'], C.TOWN_MENU['desc'],
                                    C.TOWN_MENU['buttons'])),
]
for fid, _ in new_messages:
    if fid in recs:
        raise SystemExit('new message %08x collides with an existing record' % fid)

new_books.sort(key=lambda x: x[0])
for fid, _ in new_books:
    if fid in recs:
        raise SystemExit('new book %08x collides with an existing record' % fid)

# ---------------------------------------------------------------- emit -------
added = 0
added_msg = 0


def emit(node, buf):
    global added
    if node.kind == 'rec':
        if node.fid in rewritten:
            body = rewritten[node.fid]
            buf += node.type + struct.pack('<III', len(body), 0, node.fid)
            buf += raw[node.start + 16:node.start + HDR]
            buf += body
        else:
            buf += raw[node.start:node.end]
        return
    at = len(buf)
    buf += raw[node.start:node.start + HDR]
    for c in node.children:
        emit(c, buf)
    if node.gtype == 0 and node.label == int.from_bytes(b'BOOK', 'little'):
        for fid, body in new_books:
            buf += record(b'BOOK', fid, body)
            added += 1
    struct.pack_into('<I', buf, at + 4, len(buf) - at)


tes4 = next(c for c in root.children if c.kind == 'rec' and c.type == b'TES4')

buf = bytearray()
buf += raw[tes4.start:tes4.end]
for c in root.children:
    if c is tes4:
        continue
    emit(c, buf)

if added != len(new_books):
    raise SystemExit('BOOK top group was never found; nothing was appended')

# This plugin ships no MESG records yet, so the top level group has to be made.
# Group order at the top level is a Creation Kit convention, not something the
# runtime enforces, so appending is fine.
if added_msg == 0:
    inner = b''.join(record(b'MESG', fid, body) for fid, body in new_messages)
    grup = b'GRUP' + struct.pack('<I', HDR + len(inner)) + b'MESG' + \
           struct.pack('<i', 0) + raw[root.children[1].start + 16:root.children[1].start + HDR]
    buf += grup + inner
    added_msg = len(new_messages)

# HEDR record count and next object id
t2 = index(bytes(buf))[0]
tes4b = next(c for c in t2.children if c.kind == 'rec' and c.type == b'TES4')
nrec = len(index(bytes(buf))[1]) - 1   # HEDR counts records, not the TES4 header
body = bytearray()
for t, v in fields(tes4b.body):
    if t == b'HEDR':
        ver, _, nextid = struct.unpack('<fiI', v[:12])
        want = max(nextid, max(f for f, _ in new_books + new_messages) & 0xffffff)
        v = struct.pack('<fiI', ver, nrec, want + 1) + v[12:]
    body += field(t, v)
head = b'TES4' + struct.pack('<III', len(body), tes4b.flags, tes4b.fid) + \
       raw[tes4.start + 16:tes4.start + HDR]
buf = bytearray(head + bytes(body) + bytes(buf)[tes4b.end:])

import os
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'wb').write(bytes(buf))

# ---------------------------------------------------------------- verify -----
r2, recs2 = index(bytes(buf))
cnt = collections.Counter(r.type.decode() for r in recs2.values())
print('wrote %s' % OUT)
print('  %d bytes (was %d)' % (len(buf), len(raw)))
print('  %d records: %s' % (len(recs2), dict(cnt.most_common())))
print('  rewrote %d manuals, appended %d books, %d menus'
      % (len(rewritten), added, added_msg))

missing = [f for f, _ in new_books + new_messages if f not in recs2]
if missing:
    raise SystemExit('appended books did not survive the reparse: %s' % missing)

for fid, (title, track, tier) in list(C.MANUAL_TITLES.items())[:2] + []:
    got = {t: v for t, v in fields(recs2[fid].body)}
    print('  check %08x FULL=%r MODL=%r len(DESC)=%d' %
          (fid, zstr(got[b'FULL']), zstr(got[b'MODL']), len(got[b'DESC'])))
for fid, _ in new_books[:2]:
    got = {t: v for t, v in fields(recs2[fid].body)}
    print('  check %08x EDID=%r FULL=%r' % (fid, zstr(got[b'EDID']), zstr(got[b'FULL'])))
