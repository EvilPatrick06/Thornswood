"""
Build-LastPlugin.py

Builds Thornswood-Last.esp, the small plugin that loads at the very end of the
load order, from the installed plugins and the repository's own tables. Every
byte of it comes out of this script. Nobody edits it in an editor.

WHY (issue #2468)

Patrick, 12 October: "make it so the server and client never load the cut NPCs
not even once ... currently it shows them for a split second the first time you
go in that area and then they disappear", and the dialogue pop-ups "when you go
through the White run gate ... I don't want that there like at all". The same
day: "all vanilla quests can also be cut entirely and never loaded". He
approved a small plugin at the end of the load order on 12 October, for #516
and #1394 as well as this.

WHY THE CUT ONES FLASHED, measured in the fork at its pin (9035ea46):

  The server never made them. game/gamemode.js hands the catalogue's cut list
  to setNpcPlacementExclusions, and WorldState::LoadForm refuses every one of
  those ids before it reads the record.

  Each person's own game did. Skyrim loads every placed actor of a cell from the
  plugins the moment the cell loads. The client's WorldCleanerService
  (skymp5-client/src/services/services/worldCleanerService.ts) then removes
  actors the server does not own, ONE PER FRAME, picked at random among the
  actors within 8,192 units, with disable() and delete(). With a few dozen
  placed actors in a city that is seconds of them standing there. That is the
  flash. The cleaner skips an actor that is disabled already.

  The gate talk came from vanilla quests that run in each person's own game:
  Skyrim starts every quest flagged Start Game Enabled when the game loads, and
  the Story Manager starts the others on its events (arriving at a location,
  actors near each other). SkyMP blocks Papyrus events on the client
  (blockPapyrusEventsService.ts), but dialogue, packages, force greets and
  scenes are the engine's own and run without Papyrus. The Whiterun gate's
  quest, DialogueWhiterunGuardGateStop (d1984:Skyrim.esm), is Start Game
  Enabled; its guard's WhiterunGateGuardForcegreet package (d198b) is the
  pop-up.

WHAT IT PUTS IN THE PLUGIN

  1. Every placed actor the NPC catalogue cuts (game/data/npc-population.json,
     the 1 October rules) is overridden INITIALLY DISABLED, with no enable
     parent, so no machine ever draws it and the server's reader
     (WorldState::AttachEspmRecord) never makes it. The override keeps the
     actor's base, position and editor id and nothing else: no scripts, no
     links, no enable parent, so nothing can switch it back on.
     Left alone: actors a later plugin already deleted, actors that are
     already disabled with no enable parent (they never show), and the
     authored corpses while the policy file says they stay (decision on #2468).

  2. Every vanilla quest (Skyrim.esm, Update.esm, Dawnguard.esm,
     HearthFires.esm, Dragonborn.esm), except the ones the policy file keeps
     while Patrick decides, is overridden so it can never start in anybody's
     game: Start Game Enabled is cleared, and a condition that is never true
     is put first among its Story Manager conditions, as an AND, so no Story
     Manager event can start it. Everything else on the quest is the winning
     record's own. The gate, door and arrival talk is in these quests.

  A placed actor's override needs the cell it stands in, and the worldspace
  for an exterior, so those are copied too, EXACTLY as the winning plugin has
  them, form ids moved into this plugin's numbering. A quest is copied the same
  way. The plugin's own masters are every plugin those copies name.

WHY NOT IN Thornswood-Content.esp

  A copied cell has to be the record that wins at the copy's place in the load
  order, or it undoes the cell edits of the plugins before it. 1,457 cells and
  53 worldspaces hold the cut actors, and their winners are 49 different
  plugins; Thornswood-Content.esp has the five base masters and nothing else,
  and loads before 52 plugins that edit the same records. At the end of the
  load order every copy is the winner, exactly. So everything is here.

WHY IT IS LIGHT (ESL FLAGGED)

  It adds no record of its own, only overrides, so it takes no full load order
  slot: every full plugin keeps its index, and no world reset follows from
  adding it. The server's load order already carries light plugins (#1715).

WHAT IT READS

  The load order is the NPC catalogue's own (npc-population.json loadOrder),
  read from --data, and every plugin has to be the bytes the catalogue was
  built from (sha256), except Thornswood-Content.esp, which has to be the
  repository's game/content copy. A load order that moved means the catalogue
  is rebuilt first (scripts/dev/Build-NpcPopulation.py), then this. This
  plugin is never read as an input: it is what the catalogue and the policy
  produce, and the catalogue reads past it too.

  game/data/last-plugin-policy.json is what is kept: the quests a kept
  Thornswood feature may still need, until Patrick decides each one, and
  whether the authored corpses stay. Localised names (a cell's, a quest's) are
  read out of the masters' string tables and written in plain, because this
  plugin is not localised.

WHAT IT WRITES

  game/content/Thornswood-Last.esp, and game/data/last-plugin.json, the
  manifest: the plugin's sha256, the load order it was built against, every
  cut actor it switches off and every one it leaves and why, every quest it
  stops and every quest it keeps. tests/test-2468-last-plugin.js holds the two
  together on every build, without the game.

HOW IT REACHES PEOPLE

  Like Thornswood-Content.esp at revision 2, it goes into the Nexus collection
  as a Thornswood mod, enabled and sorted last, which is Vortex window work for
  Patrick or the Vortex lane; the collection's plugin record and the servers'
  load order then carry it (docs and the steps are on #2468). Until it is in
  the servers' load order, game/gamemode.js keeps handing the server the cut
  list, and the test above holds that coupling both ways.

Usage:
    python scripts/mods/Build-LastPlugin.py --check
    python scripts/mods/Build-LastPlugin.py
    python scripts/mods/Build-LastPlugin.py --verify
    python scripts/mods/Build-LastPlugin.py --data C:\\Thornswood\\Game\\Data

--check builds it in memory and says whether the committed plugin and manifest
are those bytes. --verify reads the load order with the committed plugin at
its end and checks, record by record, that no cut actor is left able to show
and no cut quest is left able to start, and lists the gate, door and arrival
talk with what stops each. Exit 1 on any refusal.
"""

import argparse
import collections
import hashlib
import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'scripts', 'dev'))
import bsa  # noqa: E402  (the repository's archive reader)

PLUGIN = 'Thornswood-Last.esp'
CONTENT = 'Thornswood-Content.esp'
VANILLA = ('skyrim.esm', 'update.esm', 'dawnguard.esm', 'hearthfires.esm', 'dragonborn.esm')
DATA_DIR = 'C:\\Thornswood\\Game\\Data'
CATALOGUE = os.path.join(ROOT, 'game', 'data', 'npc-population.json')
POLICY = os.path.join(ROOT, 'game', 'data', 'last-plugin-policy.json')
MANIFEST = os.path.join(ROOT, 'game', 'data', 'last-plugin.json')
OUT = os.path.join(ROOT, 'game', 'content', PLUGIN)
REPO_CONTENT = os.path.join(ROOT, 'game', 'content', CONTENT)

COMPRESSED = 0x00040000
DELETED = 0x20
DISABLED = 0x800
LIGHT = 0x200
START_GAME_ENABLED = 0x0001
FORM_VERSION = 44

# The condition that is never true, the same 32 bytes Thornswood-Content.esp
# already carries on the Hearthfire house parts (#2258): GetItemCount (47) of
# Gold001 (0xF, Skyrim.esm) on the subject, less than 0. Nothing carries less
# than no gold, and a Story Manager event with no subject fails it as well.
NEVER_TRUE = struct.pack('<B3sfHHIIIIi', 4 << 5, b'\x00\x00\x00', 0.0, 47, 0,
                         0x0000000F, 0, 0, 0, -1)

# The order Skyrim writes its top groups in.
GROUP_ORDER = [b'CELL', b'WRLD', b'QUST']


# --------------------------------------------------------------- reading

def subrecords(data):
    """(tag, bytes) pairs. A subrecord longer than 65,535 bytes is preceded by
    an XXXX that carries its real size; the pair comes back whole."""
    out, i, big = [], 0, None
    while i + 6 <= len(data):
        tag = data[i:i + 4]
        size = struct.unpack_from('<H', data, i + 4)[0]
        if tag == b'XXXX':
            big = struct.unpack_from('<I', data, i + 6)[0]
            i += 6 + size
            continue
        if big is not None:
            size, big = big, None
        if i + 6 + size > len(data):
            raise ValueError('a subrecord runs past the end of its record')
        out.append((tag, data[i + 6:i + 6 + size]))
        i += 6 + size
    if i != len(data):
        raise ValueError('a record ends inside a subrecord header')
    return out


def pack_subrecords(pairs):
    out = []
    for t, b in pairs:
        if len(b) > 0xFFFF:
            out.append(b'XXXX' + struct.pack('<HI', 4, len(b)) + t + struct.pack('<H', 0) + b)
        else:
            out.append(t + struct.pack('<H', len(b)) + b)
    return b''.join(out)


class Entry(object):
    __slots__ = ('tag', 'flags', 'fid', 'off', 'size', 'ctx', 'pi')

    def __init__(self, tag, flags, fid, off, size, ctx, pi):
        self.tag, self.flags, self.fid, self.off, self.size, self.ctx, self.pi = (
            tag, flags, fid, off, size, ctx, pi)


class Plugin(object):
    def __init__(self, path, name, index):
        self.path, self.name, self.index = path, name, index
        self.buf = open(path, 'rb').read()
        b = self.buf
        if b[:4] != b'TES4':
            raise SystemExit('STOP. %s does not start with a TES4 header. Nothing was written.' % name)
        hs = struct.unpack_from('<I', b, 4)[0]
        self.hflags = struct.unpack_from('<I', b, 8)[0]
        self.header_end = 24 + hs
        self.masters = [x.rstrip(b'\x00').decode('latin1')
                        for t, x in subrecords(b[24:24 + hs]) if t == b'MAST']
        self.localised = bool(self.hflags & 0x80)
        self.strings = {}

    def owner(self, fid):
        idx = fid >> 24
        return self.masters[idx] if idx < len(self.masters) else self.name

    def gid(self, fid):
        """A form id as (owning plugin, object id), the same in every file."""
        return (self.owner(fid).lower(), fid & 0xFFFFFF)

    def data(self, e):
        raw = self.buf[e.off + 24:e.off + 24 + e.size]
        if e.flags & COMPRESSED:
            out = zlib.decompress(raw[4:])
            if len(out) != struct.unpack_from('<I', raw, 0)[0]:
                raise SystemExit('STOP. %s 0x%08X inflates to the wrong size. Nothing was written.'
                                 % (self.name, e.fid))
            return out
        return raw

    def walk(self, want):
        """Every record whose tag is in want, with where it sits.

        A placed reference's ctx is (world fid or None, cell fid, child group
        type 8 or 9, block group, sub-block group); a CELL's is (world fid or
        None, block group, sub-block group, is a world's persistent cell). A
        group is (type, label bytes). All in this file's own numbering."""
        b, out, stack = self.buf, [], []
        p, n = self.header_end, len(self.buf)
        while p + 24 <= n:
            while stack and p >= stack[-1][0]:
                stack.pop()
            tag = b[p:p + 4]
            size = struct.unpack_from('<I', b, p + 4)[0]
            if tag == b'GRUP':
                stack.append((p + size, struct.unpack_from('<i', b, p + 12)[0], b[p + 8:p + 12]))
                p += 24
                continue
            if tag in want:
                flags, fid = struct.unpack_from('<II', b, p + 8)
                ctx = None
                if tag in (b'ACHR', b'CELL'):
                    world = cell = child = block = sub = None
                    for (_, gt, lb) in stack:
                        if gt == 1:
                            world = struct.unpack('<I', lb)[0]
                        elif gt in (2, 4):
                            block = (gt, lb)
                        elif gt in (3, 5):
                            sub = (gt, lb)
                        elif gt == 6:
                            cell = struct.unpack('<I', lb)[0]
                        elif gt in (8, 9, 10):
                            child = gt
                    if tag == b'CELL':
                        ctx = (world, block, sub, world is not None and block is None)
                    else:
                        ctx = (world, cell, child, block, sub)
                out.append(Entry(tag, flags, fid, p, size, ctx, self.index))
            p += 24 + size
        return out


def string_table(data_dir, plugin, kind):
    """{string id: raw bytes} for one plugin's .STRINGS, .DLSTRINGS or
    .ILSTRINGS, loose files first and then the archives, the order the game
    reads them in. The bytes are kept as the table has them, so a name is
    written back exactly."""
    name = '%s_english.%s' % (os.path.splitext(plugin)[0].lower(), kind)
    data = None
    loose = os.path.join(data_dir, 'Strings', name)
    if os.path.isfile(loose):
        data = open(loose, 'rb').read()
    else:
        for archive in sorted(os.listdir(data_dir)):
            if not archive.lower().endswith('.bsa'):
                continue
            try:
                files = bsa.read(os.path.join(data_dir, archive), 'strings')
            except (ValueError, struct.error, zlib.error, IndexError):
                continue
            if 'strings/' + name in files:
                data = files['strings/' + name]
                break
    if data is None:
        raise SystemExit('STOP. no %s for %s in %s. Nothing was written.' % (kind, plugin, data_dir))
    count = struct.unpack_from('<I', data, 0)[0]
    base = 8 + count * 8
    out = {}
    for i in range(count):
        sid, off = struct.unpack_from('<II', data, 8 + i * 8)
        p = base + off
        if kind == 'strings':
            e = data.index(b'\x00', p)
            out[sid] = data[p:e]
        else:
            n = struct.unpack_from('<I', data, p)[0]
            out[sid] = data[p + 4:p + 4 + n].rstrip(b'\x00')
    return out


# ----------------------------------------------------------------- VMAD

class _R(object):
    def __init__(self, b):
        self.b, self.p = b, 0

    def take(self, fmt):
        v = struct.unpack_from(fmt, self.b, self.p)
        self.p += struct.calcsize(fmt)
        return v[0] if len(v) == 1 else v

    def raw(self, n):
        v = self.b[self.p:self.p + n]
        self.p += n
        return v

    def wstr(self):
        return self.raw(self.take('<H'))


def _ws(s):
    return struct.pack('<H', len(s)) + s


def _obj(r, fmt):
    if fmt == 1:
        fid, alias, unused = r.take('<IhH')
    else:
        unused, alias, fid = r.take('<HhI')
    return {'fid': fid, 'alias': alias, 'unused': unused}


def _wobj(o, fmt):
    if fmt == 1:
        return struct.pack('<IhH', o['fid'], o['alias'], o['unused'])
    return struct.pack('<HhI', o['unused'], o['alias'], o['fid'])


def _value(r, t, fmt):
    if t == 0:
        return None
    if t == 1:
        return _obj(r, fmt)
    if t == 2:
        return r.wstr()
    if t in (3, 4):
        return r.raw(4)
    if t == 5:
        return r.raw(1)
    if t in (11, 12, 13, 14, 15):
        n = r.take('<I')
        one = {11: lambda: _obj(r, fmt), 12: r.wstr, 13: lambda: r.raw(4),
               14: lambda: r.raw(4), 15: lambda: r.raw(1)}[t]
        return [one() for _ in range(n)]
    raise ValueError('a script property of type %d' % t)


def _wvalue(t, v, fmt):
    if t == 0:
        return b''
    if t == 1:
        return _wobj(v, fmt)
    if t == 2:
        return _ws(v)
    if t in (3, 4, 5):
        return v
    if t == 11:
        return struct.pack('<I', len(v)) + b''.join(_wobj(o, fmt) for o in v)
    if t == 12:
        return struct.pack('<I', len(v)) + b''.join(_ws(s) for s in v)
    return struct.pack('<I', len(v)) + b''.join(v)


def _scripts(r, ver, fmt):
    out = []
    for _ in range(r.take('<H')):
        s = {'name': r.wstr(), 'status': r.take('<B') if ver >= 4 else None, 'props': []}
        for _ in range(r.take('<H')):
            name = r.wstr()
            t = r.take('<B')
            st = r.take('<B') if ver >= 4 else None
            s['props'].append({'name': name, 'type': t, 'status': st, 'value': _value(r, t, fmt)})
        out.append(s)
    return out


def _wscripts(scripts, ver, fmt):
    out = [struct.pack('<H', len(scripts))]
    for s in scripts:
        out.append(_ws(s['name']) + (bytes([s['status']]) if ver >= 4 else b''))
        out.append(struct.pack('<H', len(s['props'])))
        for p in s['props']:
            out.append(_ws(p['name']) + bytes([p['type']]) +
                       (bytes([p['status']]) if ver >= 4 else b'') + _wvalue(p['type'], p['value'], fmt))
    return b''.join(out)


def vmad_parse(b, quest):
    """A VMAD as a tree. A quest's carries its stage fragments and its alias
    scripts after the scripts; those are read too, because alias scripts hold
    form ids."""
    r = _R(b)
    ver, fmt = r.take('<hh')
    tree = {'ver': ver, 'fmt': fmt, 'scripts': _scripts(r, ver, fmt), 'quest': None}
    if quest and r.p < len(b):
        q = {'unk': r.take('<B'), 'frags': []}
        n = r.take('<H')
        q['file'] = r.wstr()
        for _ in range(n):
            q['frags'].append((r.take('<H'), r.take('<H'), r.raw(4), r.take('<B'), r.wstr(), r.wstr()))
        q['aliases'] = []
        for _ in range(r.take('<H')):
            o = _obj(r, fmt)
            aver, afmt = r.take('<hh')
            q['aliases'].append({'obj': o, 'ver': aver, 'fmt': afmt, 'scripts': _scripts(r, aver, afmt)})
        tree['quest'] = q
    tree['rest'] = b[r.p:]
    return tree


def vmad_write(tree):
    ver, fmt = tree['ver'], tree['fmt']
    out = [struct.pack('<hh', ver, fmt), _wscripts(tree['scripts'], ver, fmt)]
    q = tree['quest']
    if q is not None:
        out.append(bytes([q['unk']]) + struct.pack('<H', len(q['frags'])) + _ws(q['file']))
        for (i, u, log, u8, sn, fn) in q['frags']:
            out.append(struct.pack('<HH', i, u) + log + bytes([u8]) + _ws(sn) + _ws(fn))
        out.append(struct.pack('<H', len(q['aliases'])))
        for a in q['aliases']:
            out.append(_wobj(a['obj'], fmt) + struct.pack('<hh', a['ver'], a['fmt']) +
                       _wscripts(a['scripts'], a['ver'], a['fmt']))
    out.append(tree['rest'])
    return b''.join(out)


def vmad_objects(tree):
    def props(scripts):
        for s in scripts:
            for p in s['props']:
                if p['type'] == 1:
                    yield p['value']
                elif p['type'] == 11:
                    for o in p['value']:
                        yield o
    for o in props(tree['scripts']):
        yield o
    if tree['quest']:
        for a in tree['quest']['aliases']:
            yield a['obj']
            for o in props(a['scripts']):
                yield o


# ------------------------------------------------- what holds a form id

# Which subrecords of each copied record type hold form ids. Anything a copied
# record carries that is in none of these lists stops the build: a form id in
# a field this does not know would keep its old plugin's numbering, which is
# the one mistake that would be found months later.
FIELDS = {
    b'CELL': {
        'fid': {b'LTMP', b'XLCN', b'XCMO', b'XCAS', b'XCIM', b'XEZN', b'XOWN', b'XCCM',
                b'XILL', b'XCWT'},
        'array': {b'XCLR'},
        'plain': {b'EDID', b'DATA', b'XCLW', b'XCLC', b'XCLL', b'MHDT', b'TVDT', b'XWEM',
                  b'LNAM', b'XNAM', b'XWCN', b'XWCU', b'XWCS', b'XRNK'},
        'strings': {b'FULL'},
        'drop': set(),
    },
    b'WRLD': {
        'fid': {b'WNAM', b'CNAM', b'NAM2', b'NAM3', b'ZNAM', b'XLCN', b'XEZN', b'LTMP', b'INAM'},
        'array': set(),
        'plain': {b'EDID', b'ONAM', b'NAMA', b'DATA', b'NAM0', b'NAM9', b'NAM4', b'DNAM',
                  b'PNAM', b'WCTR', b'MNAM', b'MHDT', b'TNAM', b'UNAM', b'XWEM', b'MODL',
                  b'MODT'},
        'strings': {b'FULL'},
        # The offset table points at byte offsets inside the plugin it came
        # from. In this file it would point at nothing, so it is left out.
        'drop': {b'OFST'},
    },
    b'QUST': {
        'fid': {b'VTCK', b'ALPC', b'ALUA', b'ALFR', b'ALRT', b'ALFC', b'ALCO', b'ALDN', b'ECOR',
                b'ALFL', b'QTGL', b'ALEQ', b'ALSP', b'KNAM', b'SPOR', b'OCOR', b'GWOR', b'NAM0',
                b'QNAM'},
        'array': {b'KWDA'},
        'plain': {b'EDID', b'DNAM', b'ENAM', b'FLTR', b'NEXT', b'INDX', b'QSDT', b'ANAM',
                  b'ALST', b'ALID', b'FNAM', b'ALED', b'ALLS', b'ALFI', b'ALFA', b'ALFE',
                  b'ALFD', b'ALCA', b'ALCL', b'ALNA', b'ALNT', b'ALEA', b'KSIZ', b'COCT',
                  b'CIS1', b'CIS2', b'QOBJ', b'QSTA', b'SCHR', b'SCTX', b'SCDA'},
        'strings': {b'FULL', b'NNAM'},
        'dlstrings': {b'CNAM'},
        'drop': set(),
    },
}


class Renumber(object):
    """Moves form ids from a source plugin's numbering into this plugin's.

    Built in two passes: the first only notes which plugins are named (so the
    master list is known), the second rewrites."""

    def __init__(self):
        self.masters = None
        self.named = set()

    def one(self, src, fid, what):
        if fid == 0:
            return 0
        idx = fid >> 24
        if idx > len(src.masters):
            raise SystemExit('STOP. %s names 0x%08X in %s, outside its masters. Nothing was written.'
                             % (src.name, fid, what))
        owner = src.owner(fid).lower()
        if self.masters is None:
            self.named.add(owner)
            return fid
        return (self.masters.index(owner) << 24) | (fid & 0xFFFFFF)

    def ctda(self, src, b, what):
        b = bytearray(b)
        # Use-global: the comparison value is a GLOBAL's form id.
        if b[0] & 0x04:
            struct.pack_into('<I', b, 4, self.one(src, struct.unpack_from('<I', b, 4)[0], what))
        # The two parameters hold a form id or a plain number depending on the
        # function. A number is moved only if its top byte names a master of
        # the source; for every source this plugin copies from today the first
        # masters keep their index, so a small number is never changed.
        for off in (12, 16):
            v = struct.unpack_from('<I', b, off)[0]
            if v and (v >> 24) <= len(src.masters):
                struct.pack_into('<I', b, off, self.one(src, v, what))
        # The reference the condition runs on.
        v = struct.unpack_from('<I', b, 24)[0]
        if v:
            struct.pack_into('<I', b, 24, self.one(src, v, what))
        return bytes(b)

    def vmad(self, src, b, quest, what):
        tree = vmad_parse(b, quest)
        if vmad_write(tree) != b:
            raise SystemExit('STOP. the scripts on %s do not read back as their own bytes. '
                             'Nothing was written.' % what)
        for o in vmad_objects(tree):
            o['fid'] = self.one(src, o['fid'], what)
        return vmad_write(tree)


def copy_record(src, entry, rn, strings, what):
    """The record's subrecords with every form id in this plugin's numbering
    and every localised string written out in plain."""
    table = FIELDS[entry.tag]
    out = []
    for t, b in subrecords(src.data(entry)):
        if t in table['drop']:
            continue
        if t in table['fid']:
            if len(b) != 4:
                raise SystemExit('STOP. %s %s is %d bytes, not a form id. Nothing was written.'
                                 % (what, t.decode(), len(b)))
            b = struct.pack('<I', rn.one(src, struct.unpack('<I', b)[0], what))
        elif t in table['array']:
            b = b''.join(struct.pack('<I', rn.one(src, v, what))
                         for v in struct.unpack('<%dI' % (len(b) // 4), b))
        elif t == b'RNAM' and entry.tag == b'WRLD':
            b = bytearray(b)
            count = struct.unpack_from('<I', b, 4)[0]
            if len(b) != 8 + 8 * count:
                raise SystemExit('STOP. %s RNAM does not hold %d references. Nothing was written.'
                                 % (what, count))
            for i in range(count):
                o = 8 + 8 * i
                struct.pack_into('<I', b, o, rn.one(src, struct.unpack_from('<I', b, o)[0], what))
            b = bytes(b)
        elif t == b'CTDA':
            b = rn.ctda(src, b, what)
        elif t == b'CNTO':
            b = struct.pack('<I', rn.one(src, struct.unpack_from('<I', b, 0)[0], what)) + b[4:]
        elif t == b'VMAD':
            b = rn.vmad(src, b, entry.tag == b'QUST', what)
        elif t in table['strings'] or t in table.get('dlstrings', ()):
            if src.localised:
                kind = 'dlstrings' if t in table.get('dlstrings', ()) else 'strings'
                sid = struct.unpack('<I', b)[0]
                text = strings(src, kind).get(sid) if sid else b''
                if text is None:
                    raise SystemExit('STOP. %s %s names string %d, which %s does not have. '
                                     'Nothing was written.' % (what, t.decode(), sid, src.name))
                b = text + b'\x00'
        elif t not in table['plain']:
            raise SystemExit('STOP. %s carries %s, which this does not know how to copy. '
                             'Nothing was written.' % (what, t.decode()))
        out.append((t, b))
    return out


# ----------------------------------------------------------- the build

def ref_key(desc):
    obj, name = desc.split(':', 1)
    return (name.lower(), int(obj, 16))


def desc_of(gid, canon):
    return '%x:%s' % (gid[1], canon[gid[0]])


def load(data_dir, catalogue):
    """The catalogue's load order, read from data_dir and held to its bytes."""
    order = [row['name'] for row in catalogue['loadOrder'] if row['name'] != PLUGIN]
    canon = {n.lower(): n for n in order}
    plugins, problems = [], []
    for i, row in enumerate([r for r in catalogue['loadOrder'] if r['name'] != PLUGIN]):
        path = os.path.join(data_dir, row['name'])
        if not os.path.isfile(path):
            problems.append('%s is not in %s' % (row['name'], data_dir))
            continue
        p = Plugin(path, row['name'], i)
        sha = hashlib.sha256(p.buf).hexdigest()
        if row['name'] == CONTENT:
            want = hashlib.sha256(open(REPO_CONTENT, 'rb').read()).hexdigest()
            if sha != want:
                problems.append('%s in %s is not the repository\'s game/content copy '
                                '(put it in place with scripts/release/Go.ps1)' % (CONTENT, data_dir))
        elif sha != row['sha256']:
            problems.append('%s in %s is not the bytes npc-population.json was built from '
                            '(rebuild the catalogue first: scripts/dev/Build-NpcPopulation.py)'
                            % (row['name'], data_dir))
        p.masters = [canon.get(m.lower(), m) for m in p.masters]
        plugins.append(p)
    if problems:
        raise SystemExit('STOP. the load order is not the one the catalogue was built from:\n  ' +
                         '\n  '.join(problems) + '\nNothing was written.')
    return order, canon, plugins


def winners(plugins, want):
    win = {}
    for p in plugins:
        for e in p.walk(want):
            win[(e.tag, p.gid(e.fid))] = e
    return win


# The package templates a force greet is made from (Skyrim.esm), and the words
# a gate, door or arrival scene is named with.
FORCE_GREET_TEMPLATES = {('skyrim.esm', 0x03C1C4)}  # ForceGreet; ForceGreetFromSitting is found by name
ARRIVAL_SCENE_WORDS = ('gate', 'intro', 'arriv', 'opening', 'welcome', 'greet')


def arrival_talk(plugins, canon):
    """Every quest whose talk fires on reaching a place, a door or a gate,
    with what ties it there. Read from the records, so it is the same list on
    any machine with this load order:

      arrives at a place   the Story Manager starts it on a change of location
      a door names it      a script on a placed door names the quest
      a trigger names it   a script on a placed trigger box names the quest
      a force greet        a ForceGreet package waits on the quest
      a scene              one of its scenes is a gate, intro or arrival scene
    """
    win = winners(plugins, {b'QUST', b'SCEN', b'PACK', b'REFR', b'DOOR'})
    doors = {g for (t, g) in win if t == b'DOOR'}
    quests = {g: e for (t, g), e in win.items() if t == b'QUST'}
    why = collections.defaultdict(set)

    def names(src, e):
        return [(t, b) for t, b in subrecords(src.data(e))]

    templates = set(FORCE_GREET_TEMPLATES)
    for (t, g), e in win.items():
        if t == b'PACK':
            ed = dict(names(plugins[e.pi], e)).get(b'EDID', b'').rstrip(b'\x00').lower()
            if ed in (b'forcegreet', b'forcegreetfromsitting'):
                templates.add(g)
    for (t, g), e in win.items():
        src = plugins[e.pi]
        if t == b'QUST':
            if dict(names(src, e)).get(b'ENAM') == b'CLOC':
                why[g].add('arrives at a place')
        elif t == b'PACK':
            pairs = names(src, e)
            pk = dict(pairs).get(b'PKCU')
            if pk is None or src.gid(struct.unpack_from('<I', pk, 4)[0]) not in templates:
                continue
            for tt, b in pairs:
                if tt == b'CTDA':
                    for off in (12, 16):
                        v = struct.unpack_from('<I', b, off)[0]
                        if v and (v >> 24) <= len(src.masters) and src.gid(v) in quests:
                            why[src.gid(v)].add('a force greet waits on it')
        elif t == b'SCEN':
            pairs = dict(names(src, e))
            ed = pairs.get(b'EDID', b'').rstrip(b'\x00').decode('latin1').lower()
            if b'PNAM' in pairs and any(w in ed for w in ARRIVAL_SCENE_WORDS):
                why[src.gid(struct.unpack('<I', pairs[b'PNAM'])[0])].add('a gate or arrival scene')
        elif t == b'REFR':
            pairs = names(src, e)
            tags = [tt for tt, _ in pairs]
            if b'VMAD' not in tags:
                continue
            base = src.gid(struct.unpack('<I', dict(pairs)[b'NAME'])[0])
            kind = 'a door names it' if base in doors else 'a trigger names it' if b'XPRM' in tags else None
            if kind is None:
                continue
            tree = vmad_parse(dict(pairs)[b'VMAD'], False)
            for o in vmad_objects(tree):
                if o['fid'] and (o['fid'] >> 24) <= len(src.masters) and src.gid(o['fid']) in quests:
                    why[src.gid(o['fid'])].add(kind)
    out = []
    for g in sorted(why):
        e = quests[g]
        ed = dict(names(plugins[e.pi], e)).get(b'EDID', b'').rstrip(b'\x00').decode('latin1')
        out.append({'quest': desc_of(g, canon), 'edid': ed, 'vanilla': g[0] in VANILLA,
                    'why': sorted(why[g])})
    return out


def build(data_dir):
    catalogue = json.load(open(CATALOGUE, encoding='utf-8'))
    policy = json.load(open(POLICY, encoding='utf-8'))
    order, canon, plugins = load(data_dir, catalogue)
    win = winners(plugins, {b'ACHR', b'CELL', b'WRLD', b'QUST'})
    tables = {}

    def strings(src, kind):
        key = (src.name, kind)
        if key not in tables:
            tables[key] = string_table(data_dir, src.name, kind)
        return tables[key]

    # 1. The cut actors.
    keep_corpses = policy['corpses']['action'] == 'keep'
    refs = {'disabled': [], 'deleted': [], 'alreadyOff': [], 'corpseKept': []}
    actors = []
    for row in catalogue['npcs']:
        if row['keep'] or row['ref'] == '14:Skyrim.esm':
            continue
        e = win.get((b'ACHR', ref_key(row['ref'])))
        if e is None:
            raise SystemExit('STOP. the catalogue cuts %s and no plugin places it. Nothing was written.'
                             % row['ref'])
        src = plugins[e.pi]
        tags = [t for t, _ in subrecords(src.data(e))]
        if e.flags & DELETED:
            refs['deleted'].append(row['ref'])
        elif e.flags & DISABLED and b'XESP' not in tags:
            refs['alreadyOff'].append(row['ref'])
        elif keep_corpses and row['reason'] == 'Authored corpse, not a living encounter':
            refs['corpseKept'].append(row['ref'])
        else:
            refs['disabled'].append(row['ref'])
            actors.append(e)

    # 2. The quests.
    kept_ids = {ref_key(q['quest']): q for q in policy['questsKept']}
    prefixes = tuple(policy.get('questEditorIdPrefixesKept', {}).keys())
    quests_cut, quests_kept = [], []
    qentries = []
    for (tag, gid), e in sorted(win.items()):
        if tag != b'QUST' or gid[0] not in VANILLA:
            continue
        src = plugins[e.pi]
        edid = dict(subrecords(src.data(e))).get(b'EDID', b'').rstrip(b'\x00').decode('latin1')
        row = {'quest': desc_of(gid, canon), 'edid': edid}
        if gid in kept_ids:
            if kept_ids[gid]['edid'] != edid:
                raise SystemExit('STOP. the policy keeps %s as %s, and it is %s. Nothing was written.'
                                 % (row['quest'], kept_ids[gid]['edid'], edid))
            quests_kept.append(dict(row, why=kept_ids[gid]['group']))
        elif prefixes and edid.startswith(prefixes):
            quests_kept.append(dict(row, why=next(policy['questEditorIdPrefixesKept'][p]
                                                   for p in prefixes if edid.startswith(p))))
        else:
            quests_cut.append(row)
            qentries.append(e)
    missing = set(kept_ids) - {ref_key(q['quest']) for q in quests_kept}
    if missing:
        raise SystemExit('STOP. the policy keeps quests no master has: %s. Nothing was written.'
                         % ', '.join(desc_of(g, canon) for g in sorted(missing)))

    # The cells and worlds the actors stand in, each from its own winner.
    cells, worlds = {}, {}
    for e in actors:
        src = plugins[e.pi]
        world, cell, child, block, sub = e.ctx
        if cell is None or child not in (8, 9):
            raise SystemExit('STOP. %s 0x%08X is not inside a cell. Nothing was written.'
                             % (src.name, e.fid))
        cg = src.gid(cell)
        if (b'CELL', cg) not in win:
            raise SystemExit('STOP. no plugin carries the cell of %s 0x%08X. Nothing was written.'
                             % (src.name, e.fid))
        cells[cg] = win[(b'CELL', cg)]
        if world is not None:
            wg = src.gid(world)
            worlds[wg] = win[(b'WRLD', wg)]
            cw = cells[cg].ctx[0]
            if cw is None or plugins[cells[cg].pi].gid(cw) != wg:
                raise SystemExit('STOP. %s 0x%08X stands in a world its cell is not in. '
                                 'Nothing was written.' % (src.name, e.fid))

    # Two passes over the same copies: names first, then numbers.
    rn = Renumber()

    def copies():
        out = {'achr': [], 'cell': {}, 'wrld': {}, 'qust': []}
        for e in actors:
            src = plugins[e.pi]
            what = '%s ACHR 0x%08X' % (src.name, e.fid)
            keep = []
            for t, b in subrecords(src.data(e)):
                if t == b'NAME':
                    keep.append((t, struct.pack('<I', rn.one(src, struct.unpack('<I', b)[0], what))))
                elif t in (b'EDID', b'DATA'):
                    keep.append((t, b))
            if [t for t, _ in keep] not in ([b'NAME', b'DATA'], [b'EDID', b'NAME', b'DATA']):
                raise SystemExit('STOP. %s does not have its base and its position. Nothing was written.'
                                 % what)
            fid = rn.one(src, e.fid, what)
            flags = (e.flags & ~(COMPRESSED | DELETED)) | DISABLED
            out['achr'].append((fid, flags, pack_subrecords(keep), e))
        for g, e in cells.items():
            src = plugins[e.pi]
            what = '%s CELL 0x%08X' % (src.name, e.fid)
            out['cell'][g] = (rn.one(src, e.fid, what), e.flags & ~COMPRESSED,
                              pack_subrecords(copy_record(src, e, rn, strings, what)), e)
        for g, e in worlds.items():
            src = plugins[e.pi]
            what = '%s WRLD 0x%08X' % (src.name, e.fid)
            out['wrld'][g] = (rn.one(src, e.fid, what), e.flags & ~COMPRESSED,
                              pack_subrecords(copy_record(src, e, rn, strings, what)), e)
        for e in qentries:
            src = plugins[e.pi]
            what = '%s QUST 0x%08X' % (src.name, e.fid)
            pairs = copy_record(src, e, rn, strings, what)
            pairs = stop_quest(pairs, what)
            out['qust'].append((rn.one(src, e.fid, what), e.flags & ~COMPRESSED,
                                pack_subrecords(pairs), e))
        return out

    copies()
    rn.named.add('skyrim.esm')  # NEVER_TRUE names Gold001
    rn.masters = [n.lower() for n in order if n.lower() in rn.named]
    made = copies()
    masters = [canon[m] for m in rn.masters]
    plugin = write_plugin(made, masters, plugins, rn)
    manifest = {
        'version': 1,
        'builtBy': 'scripts/mods/Build-LastPlugin.py',
        'issue': 2468,
        'plugin': {'name': PLUGIN, 'size': len(plugin), 'sha256': hashlib.sha256(plugin).hexdigest()},
        'loadOrder': order,
        'masters': masters,
        'counts': {'actorsOff': len(refs['disabled']), 'cells': len(made['cell']),
                   'worlds': len(made['wrld']), 'questsStopped': len(quests_cut),
                   'questsKept': len(quests_kept)},
        'refs': {k: sorted(v, key=ref_key) for k, v in refs.items()},
        'quests': {'stopped': quests_cut, 'kept': quests_kept},
        'arrivalTalk': arrival_talk(plugins, canon),
    }
    return plugin, manifest


def stop_quest(pairs, what):
    """Start Game Enabled off, and NEVER_TRUE first among the Story Manager
    conditions (the CTDAs after NEXT). First, so it is ANDed with whatever
    group follows: an OR flag on the condition before it cannot reach it."""
    out, done, nexts = [], False, 0
    for t, b in pairs:
        if t == b'DNAM' and not done:
            b = struct.pack('<H', struct.unpack_from('<H', b, 0)[0] & ~START_GAME_ENABLED) + b[2:]
            done = True
        out.append((t, b))
        if t == b'NEXT':
            nexts += 1
            out.append((b'CTDA', NEVER_TRUE))
    if not done or nexts != 1:
        raise SystemExit('STOP. %s does not have one DNAM and one NEXT. Nothing was written.' % what)
    return out


def grup(label, gtype, body):
    return b'GRUP' + struct.pack('<I', 24 + len(body)) + label + struct.pack('<iHHI', gtype, 0, 0, 0) + body


def rec(tag, flags, fid, data):
    return tag + struct.pack('<IIIIHH', len(data), flags, fid, 0, FORM_VERSION, 0) + data


def write_plugin(made, masters, plugins, rn):
    """The file: header, then CELL, WRLD and QUST groups in Skyrim's own
    shapes. Everything is sorted by form id, so the same inputs give the same
    bytes."""
    count = 0

    def r(*a):
        nonlocal count
        count += 1
        return rec(*a)

    def g(*a):
        nonlocal count
        count += 1
        return grup(*a)

    # Placed actors under their cells, persistent (8) before temporary (9).
    children = collections.defaultdict(lambda: {8: [], 9: []})
    for fid, flags, data, e in made['achr']:
        src = plugins[e.pi]
        children[src.gid(e.ctx[1])][e.ctx[2]].append((fid, flags, data))

    def cell_and_children(cg):
        cfid, cflags, cdata, ce = made['cell'][cg]
        body = b''
        for kind in (8, 9):
            items = sorted(children[cg][kind])
            if items:
                body += g(struct.pack('<I', cfid), kind,
                          b''.join(r(b'ACHR', f, i, d) for i, f, d in items))
        return r(b'CELL', cflags, cfid, cdata) + g(struct.pack('<I', cfid), 6, body)

    interior = collections.defaultdict(lambda: collections.defaultdict(list))
    exterior = collections.defaultdict(lambda: {'persistent': None,
                                                'blocks': collections.defaultdict(
                                                    lambda: collections.defaultdict(list))})
    for cg, (cfid, cflags, cdata, ce) in made['cell'].items():
        cworld, block, sub, persistent_cell = ce.ctx
        if cworld is None:
            interior[block[1]][sub[1]].append((cfid, cg))
        else:
            wg = plugins[ce.pi].gid(cworld)
            if persistent_cell:
                exterior[wg]['persistent'] = cg
            else:
                exterior[wg]['blocks'][block[1]][sub[1]].append((cfid, cg))

    out = {}
    if interior:
        body = b''
        for blabel in sorted(interior, key=lambda x: struct.unpack('<i', x)[0]):
            sb = b''
            for slabel in sorted(interior[blabel], key=lambda x: struct.unpack('<i', x)[0]):
                sb += g(slabel, 3, b''.join(cell_and_children(cg) for _, cg in sorted(interior[blabel][slabel])))
            body += g(blabel, 2, sb)
        out[b'CELL'] = g(b'CELL', 0, body)
    if made['wrld']:
        body = b''
        for wg, (wfid, wflags, wdata, we) in sorted(made['wrld'].items(), key=lambda x: x[1][0]):
            inner = b''
            if exterior[wg]['persistent'] is not None:
                inner += cell_and_children(exterior[wg]['persistent'])
            blocks = exterior[wg]['blocks']
            for blabel in sorted(blocks, key=lambda x: struct.unpack('<hh', x)[::-1]):
                sb = b''
                for slabel in sorted(blocks[blabel], key=lambda x: struct.unpack('<hh', x)[::-1]):
                    sb += g(slabel, 5, b''.join(cell_and_children(cg) for _, cg in sorted(blocks[blabel][slabel])))
                inner += g(blabel, 4, sb)
            body += r(b'WRLD', wflags, wfid, wdata) + g(struct.pack('<I', wfid), 1, inner)
        out[b'WRLD'] = g(b'WRLD', 0, body)
    if made['qust']:
        out[b'QUST'] = g(b'QUST', 0, b''.join(r(b'QUST', f, i, d) for i, f, d, e in sorted(made['qust'])))

    head = [(b'HEDR', struct.pack('<fiI', 1.71, count, 0x800)),
            (b'CNAM', b'Thornswood\x00'),
            (b'SNAM', b'Built by scripts/mods/Build-LastPlugin.py. Loads last. Do not edit.\x00')]
    for m in masters:
        head += [(b'MAST', m.encode('latin1') + b'\x00'), (b'DATA', struct.pack('<Q', 0))]
    hdata = pack_subrecords(head)
    header = b'TES4' + struct.pack('<IIIIHH', len(hdata), LIGHT, 0, 0, FORM_VERSION, 0) + hdata
    return header + b''.join(out[t] for t in GROUP_ORDER if t in out)


# ------------------------------------------------------------ checking

def read_plugin(buf, name, index):
    """A built plugin read with the same walker as the inputs."""
    p = Plugin.__new__(Plugin)
    p.path, p.name, p.index, p.buf = None, name, index, buf
    hs = struct.unpack_from('<I', buf, 4)[0]
    p.hflags = struct.unpack_from('<I', buf, 8)[0]
    p.header_end = 24 + hs
    p.masters = [x.rstrip(b'\x00').decode('latin1') for t, x in subrecords(buf[24:24 + hs]) if t == b'MAST']
    p.localised = False
    p.strings = {}
    return p


def verify(data_dir, plugin_bytes, manifest):
    """The load order with the plugin at its end: no cut actor left able to
    show, no cut quest left able to start. Returns a list of failures."""
    catalogue = json.load(open(CATALOGUE, encoding='utf-8'))
    order, canon, plugins = load(data_dir, catalogue)
    last = read_plugin(plugin_bytes, PLUGIN, len(plugins))
    canon[PLUGIN.lower()] = PLUGIN
    last.masters = [canon.get(m.lower(), m) for m in last.masters]
    if not last.hflags & LIGHT:
        return ['the plugin is not flagged light']
    plugins = plugins + [last]
    win = winners(plugins, {b'ACHR', b'QUST'})
    fails = []
    for desc in manifest['refs']['disabled']:
        e = win.get((b'ACHR', ref_key(desc)))
        tags = [t for t, _ in subrecords(plugins[e.pi].data(e))] if e else []
        if e is None or not e.flags & DISABLED or b'XESP' in tags or b'VMAD' in tags:
            fails.append('cut actor %s is left able to show' % desc)
    off = set(manifest['refs']['disabled']) | set(manifest['refs']['deleted']) | \
        set(manifest['refs']['alreadyOff']) | set(manifest['refs']['corpseKept'])
    for row in catalogue['npcs']:
        if not row['keep'] and row['ref'] != '14:Skyrim.esm' and row['ref'] not in off:
            fails.append('cut actor %s is in no list' % row['ref'])
    kept = {q['quest'] for q in manifest['quests']['kept']}
    for (tag, gid), e in win.items():
        if tag != b'QUST' or gid[0] not in VANILLA:
            continue
        d = desc_of(gid, canon)
        if d in kept:
            continue
        pairs = subrecords(plugins[e.pi].data(e))
        tags = [t for t, _ in pairs]
        dnam = dict(pairs)[b'DNAM']
        after = tags.index(b'NEXT') + 1 if b'NEXT' in tags else None
        if e.pi != last.index or struct.unpack_from('<H', dnam, 0)[0] & START_GAME_ENABLED or \
                after is None or after >= len(pairs) or pairs[after] != (b'CTDA', NEVER_TRUE):
            fails.append('vanilla quest %s is left able to start' % d)
    stopped = {q['quest'] for q in manifest['quests']['stopped']}
    for row in manifest['arrivalTalk']:
        if row['vanilla'] and row['quest'] not in stopped and row['quest'] not in kept:
            fails.append('arrival talk %s %s is in neither list' % (row['quest'], row['edid']))
    return fails


def same_or_say(path, data, label):
    have = open(path, 'rb').read() if os.path.isfile(path) else None
    if have == data:
        print('  ok    %s is these bytes' % label)
        return True
    print('  DIFFERS  %s is not what this builds' % label)
    return False


def manifest_bytes(manifest):
    return (json.dumps(manifest, indent=1, ensure_ascii=False) + '\n').encode('utf-8')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=os.environ.get('THORNSWOOD_DATA', DATA_DIR))
    ap.add_argument('--check', action='store_true', help='build in memory and compare; write nothing')
    ap.add_argument('--verify', action='store_true', help='check the committed plugin in the load order')
    args = ap.parse_args()

    if args.verify:
        manifest = json.load(open(MANIFEST, encoding='utf-8'))
        fails = verify(args.data, open(OUT, 'rb').read(), manifest)
        for f in fails[:40]:
            print('  FAIL  ' + f)
        if fails:
            print('STOP. %d problem(s).' % len(fails))
            return 1
        c = manifest['counts']
        print('  ok    %d cut actors are off and nothing can switch them on; %d vanilla quests '
              'cannot start; %d kept for Patrick\'s decision' % (c['actorsOff'], c['questsStopped'], c['questsKept']))
        return 0

    plugin, manifest = build(args.data)
    c = manifest['counts']
    print('Built %s: %s bytes, %d masters' % (PLUGIN, format(len(plugin), ','), len(manifest['masters'])))
    print('  %d cut actors off, in %d cells and %d worldspaces' % (c['actorsOff'], c['cells'], c['worlds']))
    print('  left as they are: %d deleted by a plugin, %d already off, %d authored corpses kept'
          % (len(manifest['refs']['deleted']), len(manifest['refs']['alreadyOff']),
             len(manifest['refs']['corpseKept'])))
    print('  %d vanilla quests stopped, %d kept for a decision' % (c['questsStopped'], c['questsKept']))
    fails = verify(args.data, plugin, manifest)
    if fails:
        for f in fails[:40]:
            print('  FAIL  ' + f)
        print('STOP. what this built does not verify. Nothing was written.')
        return 1
    print('  ok    read back in the load order: every cut actor off, every cut quest unable to start')
    if args.check:
        a = same_or_say(OUT, plugin, 'game/content/' + PLUGIN)
        b = same_or_say(MANIFEST, manifest_bytes(manifest), 'game/data/last-plugin.json')
        return 0 if a and b else 1
    with open(OUT, 'wb') as f:
        f.write(plugin)
    with open(MANIFEST, 'wb') as f:
        f.write(manifest_bytes(manifest))
    print('Wrote game/content/%s and game/data/last-plugin.json' % PLUGIN)
    return 0


if __name__ == '__main__':
    sys.exit(main())
