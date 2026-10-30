"""
last_recipe.py

The recipe for Thornswood-Last.esp (#2791): how each machine builds the
plugin from the plugins it already has, so the plugin itself is never handed
on by Thornswood.

WHY (#2791, Patrick's A of 26 Oct 2026 on #3721)

Thornswood-Last.esp copies records from the winning plugins of the load
order: 15,543 of its records belong to 31 other authors' plugins, and many of
those authors' pages ask for their permission before their files are changed
or handed on. Patrick decided that Thornswood ships only a recipe, which
record wins and from which plugin, and that the installer and the box build
the plugin from the plugins each machine already has. Then none of those
records is ever shared by Thornswood.

WHAT A RECIPE IS

A list of steps that write the plugin from start to end. Each step is one of:

  LIT  bytes Thornswood wrote itself: the file's header, the groups' and the
       records' headers, a renumbered form id, a count or a condition the
       build sets, a subrecord the build adds
  REC  "the record at this offset of this plugin": it is read and inflated,
       and the steps after it copy from it
  CPY  so many bytes of that record, from this offset
  STR  one string of a string table (a localised name, written out in plain)

and the sha256 and size of every plugin and string table a step reads, and
of the plugin it makes. Nothing of another author's record is in it: every
byte of theirs comes out of the machine's own copy of their plugin, which the
recipe names by its sha256. A copy that differs makes nothing.

make() writes a recipe from what Build-LastPlugin.py built, and apply() makes
the plugin from a recipe. The builder runs both on every build and stops when
apply() does not give back the plugin it built, byte for byte, so a recipe
that is written always makes its plugin.

HOW make() TELLS THEIRS FROM OURS. Each record of the plugin is a copy of one
record of the load order, its winning one, with form ids renumbered,
localised names written out, some subrecords left out and a few set or added
(Build-LastPlugin.py, copy_record and the steps after it). The subrecords of
the two are lined up, exact matches first: an unchanged subrecord is copied
whole, a changed one is copied wherever its bytes are still the source's
(a renumbered form id differs only in its first byte), a localised name is
its string, and only what differs is written as LIT. A subrecord the build
added (a location, a parent, the condition that is never true) is LIT. Twelve
bytes in a row written as LIT that are still somewhere in the source record
stop the build, because then the line-up missed a copy and the recipe would
hand on something of theirs.

THE FILE (game/data/last-plugin.recipe), little endian, a varint is LEB128:

  b'TSLR' 1                    magic and version
  u32 size, 32 bytes sha256    of the plugin it makes
  varint n, then n sources:    u8 kind (0 a plugin, 1 a string table),
                               varint length and the name in UTF-8,
                               varint size, 32 bytes sha256
  steps to the end:            0 LIT varint n, n bytes
                               1 REC varint source, varint offset
                               2 CPY varint offset, varint n
                               3 STR varint source, varint string id

A string table is named the way the game names it, skyrim_english.strings,
and found the way the game finds it: the loose file under Data\\Strings
first, then each archive of Data in name order that holds strings\\<name>.
"""

import difflib
import hashlib
import struct
import zlib

MAGIC = b'TSLR\x01'
COMPRESSED = 0x00040000
PLUGIN_SOURCE, TABLE_SOURCE = 0, 1
LIT, REC, CPY, STR = 0, 1, 2, 3
# A LIT run this long that is still in the source record means the line-up
# missed a copy.
LEAK = 12


class RecipeError(Exception):
    pass


# ------------------------------------------------------------ encoding

def _varint(n):
    if n < 0:
        raise RecipeError('a recipe number cannot be negative (%d)' % n)
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


class _Reader(object):
    def __init__(self, b):
        self.b, self.p = b, 0

    def byte(self):
        if self.p >= len(self.b):
            raise RecipeError('the recipe ends in the middle of a step')
        v = self.b[self.p]
        self.p += 1
        return v

    def varint(self):
        n, shift = 0, 0
        while True:
            b = self.byte()
            n |= (b & 0x7F) << shift
            if not b & 0x80:
                return n
            shift += 7
            if shift > 63:
                raise RecipeError('a recipe number runs past 64 bits')

    def raw(self, n):
        if self.p + n > len(self.b):
            raise RecipeError('the recipe ends in the middle of a step')
        v = self.b[self.p:self.p + n]
        self.p += n
        return v


# ------------------------------------------------------------ records

def raw_subrecords(d):
    """(header start, body start, body end, tag) for each subrecord of a
    record's data, with an XXXX size before a long one counted as its
    header."""
    out, i = [], 0
    while i + 6 <= len(d):
        hs = i
        tag = d[i:i + 4]
        size = struct.unpack_from('<H', d, i + 4)[0]
        if tag == b'XXXX':
            if size != 4 or i + 16 > len(d):
                raise RecipeError('an XXXX subrecord is not four bytes and a header')
            size = struct.unpack_from('<I', d, i + 6)[0]
            i += 10
            tag = d[i:i + 4]
        body = i + 6
        end = body + size
        if end > len(d):
            raise RecipeError('a subrecord runs past the end of its record')
        out.append((hs, body, end, tag))
        i = end
    if i != len(d):
        raise RecipeError('a record ends inside a subrecord header')
    return out


def record_data(buf, off):
    """The data of the record at off, inflated when it is compressed."""
    if off + 24 > len(buf) or buf[off:off + 4] == b'GRUP':
        raise RecipeError('there is no record at offset %d' % off)
    size, flags = struct.unpack_from('<II', buf, off + 4)
    raw = buf[off + 24:off + 24 + size]
    if len(raw) != size:
        raise RecipeError('the record at offset %d runs past the end of its plugin' % off)
    if flags & COMPRESSED:
        want = struct.unpack_from('<I', raw, 0)[0]
        out = zlib.decompress(raw[4:])
        if len(out) != want:
            raise RecipeError('the record at offset %d inflates to the wrong size' % off)
        return out
    return raw


def table_strings(data, kind):
    """{string id: bytes} of a .STRINGS, .DLSTRINGS or .ILSTRINGS table, the
    way Build-LastPlugin.py reads one."""
    count = struct.unpack_from('<I', data, 0)[0]
    base = 8 + count * 8
    out = {}
    for i in range(count):
        sid, off = struct.unpack_from('<II', data, 8 + i * 8)
        p = base + off
        if kind == 'strings':
            out[sid] = data[p:data.index(b'\x00', p)]
        else:
            n = struct.unpack_from('<I', data, p)[0]
            out[sid] = data[p + 4:p + 4 + n].rstrip(b'\x00')
    return out


def table_kind(name):
    return name.rsplit('.', 1)[-1].lower()


# ------------------------------------------------------------ writing

class _Writer(object):
    def __init__(self):
        self.out = bytearray()
        self.lit = bytearray()
        self.cur = None
        self.cpy = None     # (offset, length) of a copy still being added to
        self.made = 0
        self.lit_bytes = 0

    def _flush_cpy(self):
        if self.cpy:
            self.out += bytes([CPY]) + _varint(self.cpy[0]) + _varint(self.cpy[1])
            self.cpy = None

    def _flush_lit(self):
        if self.lit:
            self.out += bytes([LIT]) + _varint(len(self.lit)) + bytes(self.lit)
            self.lit = bytearray()

    def literal(self, b):
        if b:
            self._flush_cpy()
            self.lit += b
            self.made += len(b)
            self.lit_bytes += len(b)

    def record(self, source, off):
        if self.cur != (source, off):
            self._flush_cpy()
            self._flush_lit()
            self.out += bytes([REC]) + _varint(source) + _varint(off)
            self.cur = (source, off)

    def copy(self, off, n):
        if n <= 0:
            return
        self._flush_lit()
        if self.cpy and self.cpy[0] + self.cpy[1] == off:
            self.cpy = (self.cpy[0], self.cpy[1] + n)
        else:
            self._flush_cpy()
            self.cpy = (off, n)
        self.made += n

    def string(self, source, sid, n):
        self._flush_cpy()
        self._flush_lit()
        self.out += bytes([STR]) + _varint(source) + _varint(sid)
        self.made += n

    def done(self):
        self._flush_cpy()
        self._flush_lit()
        return bytes(self.out)


def make(plugin, index, plugins, tables, what=''):
    """The recipe for plugin, the bytes Build-LastPlugin.py built.

    index: {(tag, form id as written): (record data as written, entry)} for
    every record the build made, entry being the source record
    (Build-LastPlugin.py's Entry, read from plugins[entry.pi]).
    tables: {(source plugin name, kind): (table file name, raw bytes)} for
    every string table the build read.

    Returns (recipe bytes, stats)."""
    w = _Writer()
    sources, at = [], {}

    def source(kind, name, data):
        key = (kind, name.lower())
        if key not in at:
            at[key] = len(sources)
            sources.append((kind, name, len(data), hashlib.sha256(data).digest()))
        return at[key]

    parsed = {}

    def strings_of(src):
        """[(table source, kind, {id: text})] for the tables of src's own."""
        out = []
        for (pname, kind), (fname, data) in sorted(tables.items()):
            if pname.lower() != src.name.lower():
                continue
            if fname not in parsed:
                parsed[fname] = table_strings(data, kind)
            out.append((fname, data, parsed[fname]))
        return out

    stats = {'records': 0, 'litInRecords': 0, 'addedSubrecords': {}, 'changedSubrecords': {}}
    if plugin[:4] != b'TES4':
        raise RecipeError('%s does not start with a TES4 header' % what)
    p = 24 + struct.unpack_from('<I', plugin, 4)[0]
    w.literal(plugin[:p])
    seen = set()
    while p < len(plugin):
        if p + 24 > len(plugin):
            raise RecipeError('%s ends inside a header' % what)
        tag = plugin[p:p + 4]
        if tag == b'GRUP':
            w.literal(plugin[p:p + 24])
            p += 24
            continue
        size, flags, fid = struct.unpack_from('<III', plugin, p + 4)
        key = (tag, fid)
        if key not in index or key in seen:
            raise RecipeError('%s has %s 0x%08X, which the build did not make once' % (what, tag.decode(), fid))
        seen.add(key)
        data, e = index[key]
        if plugin[p + 24:p + 24 + size] != data:
            raise RecipeError('%s %s 0x%08X is not the data the build made' % (what, tag.decode(), fid))
        w.literal(plugin[p:p + 24])
        src = plugins[e.pi]
        si = source(PLUGIN_SOURCE, src.name, src.buf)
        sdata = record_data(src.buf, e.off)
        before = w.lit_bytes
        _record_steps(w, si, e.off, data, sdata, src, strings_of, source, stats,
                      '%s %s 0x%08X' % (src.name, tag.decode(), e.fid))
        stats['litInRecords'] += w.lit_bytes - before
        stats['records'] += 1
        p += 24 + size
    if len(seen) != len(index):
        raise RecipeError('%s lacks %d record(s) the build made' % (what, len(index) - len(seen)))
    steps = w.done()
    if w.made != len(plugin):
        raise RecipeError('the recipe makes %d bytes, not %d' % (w.made, len(plugin)))
    head = bytearray(MAGIC + struct.pack('<I', len(plugin)) + hashlib.sha256(plugin).digest())
    head += _varint(len(sources))
    for kind, name, size, sha in sources:
        n = name.encode('utf-8')
        head += bytes([kind]) + _varint(len(n)) + n + _varint(size) + sha
    stats['sources'] = len(sources)
    stats['litBytes'] = w.lit_bytes
    return bytes(head) + steps, stats


def _record_steps(w, si, off, data, sdata, src, strings_of, source, stats, what):
    w.record(si, off)
    out = raw_subrecords(data)
    srcs = raw_subrecords(sdata)
    a = [(t, data[b:e]) for hs, b, e, t in out]
    b_ = [(t, sdata[b:e]) for hs, b, e, t in srcs]
    sm = difflib.SequenceMatcher(None, a, b_, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == 'equal':
            for k in range(i2 - i1):
                hs, _, e, _ = srcs[j1 + k]
                w.copy(hs, e - hs)
            continue
        if op == 'insert':          # left out of the copy
            continue
        pairs = _pair(a, b_, i1, i2, j1, j2) if op == 'replace' else {}
        for i in range(i1, i2):
            ohs, ob, oe, ot = out[i]
            match = pairs.get(i)
            if match is None:
                # A subrecord the build added: ours.
                _no_leak(data[ob:oe], sdata, what + ' ' + ot.decode())
                w.literal(data[ohs:oe])
                stats['addedSubrecords'][ot.decode()] = stats['addedSubrecords'].get(ot.decode(), 0) + 1
                continue
            shs, sb, se, _ = srcs[match]
            if data[ohs:ob] == sdata[shs:sb]:
                w.copy(shs, sb - shs)
            else:
                w.literal(data[ohs:ob])
            _body_steps(w, data[ob:oe], sdata, sb, se, src, strings_of, source, what + ' ' + ot.decode())
            stats['changedSubrecords'][ot.decode()] = stats['changedSubrecords'].get(ot.decode(), 0) + 1


def _alike(o, s):
    """How many bytes two subrecord bodies have in common."""
    if len(o) == len(s):
        return sum(1 for x, y in zip(o, s) if x == y)
    return sum(m.size for m in difflib.SequenceMatcher(None, o, s, autojunk=False).get_matching_blocks())


def _pair(a, b, i1, i2, j1, j2):
    """{output subrecord: source subrecord} for a run of changed ones: of
    the same tag, in order, each source one used once, the pairs with the most
    bytes in common. A condition the build put first among a quest's is then
    left unpaired, as ours, and the quest's own condition pairs with its
    renumbered copy."""
    n, m = i2 - i1, j2 - j1
    best = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            v = max(best[i + 1][j], best[i][j + 1])
            (ot, ob), (st, sb) = a[i1 + i], b[j1 + j]
            if ot == st:
                v = max(v, _alike(ob, sb) + 1 + best[i + 1][j + 1])
            best[i][j] = v
    out, i, j = {}, 0, 0
    while i < n and j < m:
        (ot, ob), (st, sb) = a[i1 + i], b[j1 + j]
        if ot == st and best[i][j] == _alike(ob, sb) + 1 + best[i + 1][j + 1]:
            out[i1 + i] = j1 + j
            i, j = i + 1, j + 1
        elif best[i][j] == best[i + 1][j]:
            i += 1
        else:
            j += 1
    return out


def _body_steps(w, o, sdata, sb, se, src, strings_of, source, what):
    s = sdata[sb:se]
    if len(o) == len(s):
        k = 0
        while k < len(o):
            j = k
            same = o[k] == s[k]
            while j < len(o) and (o[j] == s[j]) == same:
                j += 1
            if same:
                w.copy(sb + k, j - k)
            else:
                _no_leak(o[k:j], sdata, what)
                w.literal(o[k:j])
            k = j
        return
    if len(s) == 4 and o.endswith(b'\x00'):
        sid = struct.unpack('<I', s)[0]
        for fname, tdata, table in strings_of(src):
            if table.get(sid) == o[:-1]:
                w.string(source(TABLE_SOURCE, fname, tdata), sid, len(o) - 1)
                w.literal(b'\x00')
                return
    sm = difflib.SequenceMatcher(None, o, s, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == 'equal':
            w.copy(sb + j1, j2 - j1)
        elif op in ('replace', 'delete'):
            piece = o[i1:i2]
            _no_leak(piece, sdata, what)
            w.literal(piece)


def _no_leak(piece, sdata, what):
    """Stops when LEAK bytes in a row of piece, written as our own, are
    still in the source record. A run of padding or of one value (zeros, a
    blank float) says nothing of whose it is, so a window needs four different
    byte values to count."""
    for k in range(0, len(piece) - LEAK + 1):
        win = piece[k:k + LEAK]
        if len(set(win)) >= 4 and win in sdata:
            raise RecipeError('%s: bytes written as our own are still in the source record, '
                              'so the recipe would hand them on' % what)


# ------------------------------------------------------------ reading

def read_header(recipe):
    """(size, sha256, [(kind, name, size, sha256)], reader at the steps)."""
    if recipe[:len(MAGIC)] != MAGIC:
        raise RecipeError('this is not a version 1 recipe for Thornswood-Last.esp')
    r = _Reader(recipe)
    r.raw(len(MAGIC))
    size = struct.unpack('<I', r.raw(4))[0]
    sha = r.raw(32)
    sources = []
    for _ in range(r.varint()):
        kind = r.byte()
        name = r.raw(r.varint()).decode('utf-8')
        sources.append((kind, name, r.varint(), r.raw(32)))
    return size, sha, sources, r


def apply(recipe, read_plugin, read_table):
    """The plugin a recipe makes. read_plugin(name) and read_table(name)
    return a source's bytes, or None when this machine has none; each is held
    to the sha256 the recipe names."""
    size, sha, sources, r = read_header(recipe)
    got = {}

    def bytes_of(i):
        if i >= len(sources):
            raise RecipeError('a step names source %d of %d' % (i, len(sources)))
        if i not in got:
            kind, name, n, want = sources[i]
            data = (read_plugin if kind == PLUGIN_SOURCE else read_table)(name)
            if data is None:
                raise RecipeError('%s is not on this machine' % name)
            if len(data) != n or hashlib.sha256(data).digest() != want:
                raise RecipeError('%s is not the copy the recipe was written for' % name)
            got[i] = data
        return got[i]

    tables = {}
    out = bytearray()
    cur = None
    while r.p < len(recipe):
        op = r.byte()
        if op == LIT:
            out += r.raw(r.varint())
        elif op == REC:
            i, off = r.varint(), r.varint()
            if i >= len(sources) or sources[i][0] != PLUGIN_SOURCE:
                raise RecipeError('a record step names a source that is not a plugin')
            cur = record_data(bytes_of(i), off)
        elif op == CPY:
            off, n = r.varint(), r.varint()
            if cur is None or off + n > len(cur):
                raise RecipeError('a copy step runs past its record')
            out += cur[off:off + n]
        elif op == STR:
            i, sid = r.varint(), r.varint()
            if i >= len(sources) or sources[i][0] != TABLE_SOURCE:
                raise RecipeError('a string step names a source that is not a string table')
            if i not in tables:
                tables[i] = table_strings(bytes_of(i), table_kind(sources[i][1]))
            if sid not in tables[i]:
                raise RecipeError('%s has no string %d' % (sources[i][1], sid))
            out += tables[i][sid]
        else:
            raise RecipeError('the recipe has a step of kind %d, which version 1 does not have' % op)
    if len(out) != size or hashlib.sha256(bytes(out)).digest() != sha:
        raise RecipeError('the recipe did not make the plugin it names')
    return bytes(out)
