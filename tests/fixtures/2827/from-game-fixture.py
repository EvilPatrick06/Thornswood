"""A made-up Skyrim Data folder for #2827, with nothing of Bethesda's in it.

    python from-game-fixture.py <folder>            the archives
    python from-game-fixture.py <folder> --edited   and edited-startmenu.swf
    python from-game-fixture.py <folder> --changed  the same game with one byte
                                                    changed in a notice and one in
                                                    the menu, as a game on another
                                                    build would differ

launcher\\app\\FromGame.cs makes the start menu and the notice board's two
meshes from a person's own game, and must come to the same bytes as
scripts\\mods\\Build-StartMenu.py and scripts\\mods\\Build-NoticeBoard.py do.
The real game is only on a machine that has it, so this writes archives of
the same shape, every byte from the numbers below: the archives
Build-NoticeBoard.py reads, with a mesh at every path its PARTS name, and
Skyrim - Interface.bsa with an interface\\startmenu.swf. FixtureBoard.cs and
FixtureMenu.cs beside this are what those two scripts wrote from it, and
tests\\test-2827-from-game.ps1 holds the launcher's build to them.

The meshes are small and wrong to look at, but carry every case the build
meets: nodes inside nodes, turned and scaled; a hidden node and a hidden
shape; a node kind the build skips; extra data on shapes and shaders; alpha;
vertex layouts with and without tangents and colours; normals along an axis;
a texture set found by a name in any case; static bodies and convex shapes;
a mesh in both mesh archives (the first wins). The archives carry every way
an archive stores a file: packed and not, against the archive's own default,
with and without the name before the data, and LZ4 frames with and without
block and content checksums, a raw block, and several blocks.

--edited also writes edited-startmenu.swf, the menu with a few shapes
changed the way Thornswood's menu changed Skyrim's, which is what
Build-StartMenu.py takes as the edited file. It needs Python's zlib, which
must be the classic one (Build-StartMenu.py checks); the archives need
nothing outside Python itself, so every machine writes the same bytes.
"""
import os
import struct
import sys


class Numbers(object):
    """A fixed stream of numbers (a 64 bit LCG), the same on every machine and
    every Python, which random is not promised to be."""

    def __init__(self, seed):
        self.s = seed

    def next(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        return self.s >> 33

    def below(self, n):
        return self.next() % n

    def between(self, lo, hi):
        return lo + (hi - lo) * (self.next() / float(1 << 31))

    def raw(self, n):
        return bytes(self.below(256) for _ in range(n))


# ------------------------------------------------------------------ xxhash32 --
P1, P2, P3, P4, P5 = 2654435761, 2246822519, 3266489917, 668265263, 374761393
M32 = 0xFFFFFFFF


def rotl(x, r):
    return ((x << r) | (x >> (32 - r))) & M32


def xxh32(b, seed=0):
    n, i = len(b), 0
    if n >= 16:
        v = [(seed + P1 + P2) & M32, (seed + P2) & M32, seed & M32, (seed - P1) & M32]
        while i + 16 <= n:
            for k in range(4):
                v[k] = (rotl((v[k] + struct.unpack_from('<I', b, i)[0] * P2) & M32, 13) * P1) & M32
                i += 4
        h = (rotl(v[0], 1) + rotl(v[1], 7) + rotl(v[2], 12) + rotl(v[3], 18)) & M32
    else:
        h = (seed + P5) & M32
    h = (h + n) & M32
    while i + 4 <= n:
        h = (rotl((h + struct.unpack_from('<I', b, i)[0] * P3) & M32, 17) * P4) & M32
        i += 4
    while i < n:
        h = (rotl((h + b[i] * P5) & M32, 11) * P1) & M32
        i += 1
    h ^= h >> 15
    h = (h * P2) & M32
    h ^= h >> 13
    h = (h * P3) & M32
    h ^= h >> 16
    return h


# ----------------------------------------------------------------------- LZ4 --
def lz4_block(src):
    """One LZ4 block, greedy, within the format's end rules (the last five
    bytes are literals, and no match starts in the last twelve)."""
    n, out, table, anchor, i = len(src), bytearray(), {}, 0, 0
    while i + 12 <= n:
        key = src[i:i + 4]
        cand = table.get(key)
        table[key] = i
        if cand is None or i - cand > 65535:
            i += 1
            continue
        m = 4
        while i + m < n - 5 and src[cand + m] == src[i + m]:
            m += 1
        lit = i - anchor
        tok_l, tok_m = min(lit, 15), min(m - 4, 15)
        out.append((tok_l << 4) | tok_m)
        if lit >= 15:
            r = lit - 15
            while r >= 255:
                out.append(255)
                r -= 255
            out.append(r)
        out += src[anchor:i]
        out += struct.pack('<H', i - cand)
        if m - 4 >= 15:
            r = m - 4 - 15
            while r >= 255:
                out.append(255)
                r -= 255
            out.append(r)
        i += m
        anchor = i
    lit = n - anchor
    out.append(min(lit, 15) << 4)
    if lit >= 15:
        r = lit - 15
        while r >= 255:
            out.append(255)
            r -= 255
        out.append(r)
    out += src[anchor:]
    return bytes(out)


def lz4_frame(data, block=65536, block_sums=False, content=False, raw_first=False):
    flg = 0x60 | (0x10 if block_sums else 0) | (0x08 if content else 0) | (0x04 if content else 0)
    bd = 0x40  # 64 KB blocks
    desc = bytes([flg, bd]) + (struct.pack('<Q', len(data)) if content else b'')
    out = bytearray(struct.pack('<I', 0x184D2204)) + desc + bytes([(xxh32(desc) >> 8) & 0xFF])
    for k, at in enumerate(range(0, len(data), block)):
        chunk = data[at:at + block]
        packed = lz4_block(chunk)
        if (raw_first and k == 0) or len(packed) >= len(chunk):
            body, size = chunk, len(chunk) | 0x80000000
        else:
            body, size = packed, len(packed)
        out += struct.pack('<I', size) + body
        if block_sums:
            out += struct.pack('<I', xxh32(body))
    out += struct.pack('<I', 0)
    if content:
        out += struct.pack('<I', xxh32(data))
    return bytes(out)


# ------------------------------------------------------------------- archives --
def archive(path, files, compressed=False, embed=False, toggle=(), frames=None):
    """A BSA version 105. files: [(folder, name, bytes)], in order. A path in
    toggle is stored the other way from the archive's default; frames gives
    the lz4_frame options for a path."""
    frames = frames or {}
    folders, by = [], {}
    for folder, name, data in files:
        if folder not in by:
            by[folder] = []
            folders.append((folder, by[folder]))
        by[folder].append((name, data))
    flags = 0x3 | (0x4 if compressed else 0) | (0x100 if embed else 0)
    names = b''.join(n.encode('ascii') + b'\0' for _, l in folders for n, _ in l)
    fold_len = sum(len(f) + 1 for f, _ in folders)
    nfiles = sum(len(l) for _, l in folders)
    head = 36
    recs = 24 * len(folders)
    blocks_len = sum(1 + len(f) + 1 + 16 * len(l) for f, l in folders)
    data_at = head + recs + blocks_len + len(names)
    out = bytearray(struct.pack('<4sIIIIIIIHH', b'BSA\0', 105, head, flags, len(folders), nfiles,
                                fold_len, len(names), 0, 0))
    body, entries = bytearray(), []
    for folder, l in folders:
        for name, data in l:
            key = folder + '\\' + name
            packed = compressed ^ (key in toggle)
            stored = data
            if packed:
                stored = struct.pack('<I', len(data)) + lz4_frame(data, **frames.get(key, {}))
            if embed:
                p = key.encode('ascii')
                stored = bytes([len(p)]) + p + stored
            size = len(stored) | (0x40000000 if key in toggle else 0)
            entries.append((size, data_at + len(body)))
            body += stored
    at = head + recs
    k = 0
    for i, (folder, l) in enumerate(folders):
        out += struct.pack('<QIIQ', 0x1000 + i, len(l), 0, at)
        at += 1 + len(folder) + 1 + 16 * len(l)
    for i, (folder, l) in enumerate(folders):
        out += bytes([len(folder) + 1]) + folder.encode('ascii') + b'\0'
        for j in range(len(l)):
            out += struct.pack('<QII', 0x2000 + k, entries[k][0], entries[k][1])
            k += 1
    out += names + body
    with open(path, 'wb') as f:
        f.write(out)


# ----------------------------------------------------------------------- NIFs --
class Nif(object):
    def __init__(self):
        self.blocks, self.strings = [], []

    def string(self, s):
        if s not in self.strings:
            self.strings.append(s)
        return self.strings.index(s)

    def add(self, kind, body=b''):
        self.blocks.append([kind, body])
        return len(self.blocks) - 1

    def av(self, name, flags, t, rot, sc, extra=(), controller=-1, collision=-1):
        return (struct.pack('<iI', self.string(name), len(extra)) + b''.join(struct.pack('<i', e) for e in extra) +
                struct.pack('<iI', controller, flags) + struct.pack('<3f', *t) + struct.pack('<9f', *rot) +
                struct.pack('<fi', sc, collision))

    def node(self, at, kind, name, flags, t, rot, sc, kids, collision=-1):
        self.blocks[at] = [kind, self.av(name, flags, t, rot, sc, collision=collision) +
                           struct.pack('<I', len(kids)) + b''.join(struct.pack('<i', k) for k in kids) +
                           struct.pack('<I', 0)]

    def bytes(self):
        kinds = []
        for k, _ in self.blocks:
            if k not in kinds:
                kinds.append(k)
        sized = lambda s: struct.pack('<I', len(s)) + s.encode('ascii')
        short = lambda s: bytes([len(s) + 1]) + s.encode('ascii') + b'\0'
        out = b'Gamebryo File Format, Version 20.2.0.7\n'
        out += struct.pack('<IBIII', 0x14020007, 1, 12, len(self.blocks), 100)
        out += short('fixture') + short('') + short('')
        out += struct.pack('<H', len(kinds)) + b''.join(sized(k) for k in kinds)
        out += b''.join(struct.pack('<H', kinds.index(k)) for k, _ in self.blocks)
        out += b''.join(struct.pack('<I', len(b)) for _, b in self.blocks)
        out += struct.pack('<II', len(self.strings), max([len(s) for s in self.strings] + [0]))
        out += b''.join(sized(s) for s in self.strings) + struct.pack('<I', 0)
        out += b''.join(b for _, b in self.blocks) + struct.pack('<Ii', 1, 0)
        return out


IDENT = (1, 0, 0, 0, 1, 0, 0, 0, 1)


def turn(rx, ry, rz):
    """A rotation matrix as an exporter writes one, in float32 (sines from a
    small table, so no maths library decides a bit)."""
    s = {0: (0.0, 1.0), 90: (1.0, 0.0), 180: (0.0, -1.0), -90: (-1.0, 0.0),
         30: (0.5, 0.8660254037844386), -45: (-0.7071067811865476, 0.7071067811865476),
         12: (0.20791169081775934, 0.9781476007338057), 7: (0.12186934340514748, 0.992546151641322)}
    sx, cx = s[rx]
    sy, cy = s[ry]
    sz, cz = s[rz]
    X = ((1, 0, 0), (0, cx, -sx), (0, sx, cx))
    Y = ((cy, 0, sy), (0, 1, 0), (-sy, 0, cy))
    Z = ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))
    mul = lambda A, B: tuple(tuple(sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)) for i in range(3))
    R = mul(mul(Z, Y), X)
    return tuple(struct.unpack('<f', struct.pack('<f', R[i][j]))[0] for i in range(3) for j in range(3))


def desc_of(uv=True, normal=True, tangent=True, colour=True):
    """A vertex layout: position and bitangent x first, then each part in turn."""
    at, offs, attrs = 4, {}, 0x1
    for k, bit, on in ((2, 0x2, uv), (4, 0x8, normal), (5, 0x10, tangent), (6, 0x20, colour)):
        if on:
            offs[k] = at
            at += 1
            attrs |= bit
    d = at
    for k, o in offs.items():
        d |= o << (4 * k)
    return d | (attrs << 44)


def half(x):
    return struct.pack('<e', x)


def shape_block(nif, rnd, name, desc, nv, ntri, shader, alpha=-1, flags=524302, t=(0, 0, 0), rot=IDENT, sc=1.0,
                extra=(), axis_normals=False, spread=40.0):
    vsize = (desc & 0xF) * 4
    attrs = (desc >> 44) & 0xFFF
    off = lambda k: ((desc >> (4 * k)) & 0xF) * 4
    raw = bytearray()
    axes = [(255, 127, 127), (0, 128, 127), (127, 128, 255), (128, 127, 0), (127, 255, 128), (128, 0, 127)]
    for v in range(nv):
        b = bytearray(vsize)
        bx = (0.0, 1.0, -1.0, 0.25)[v % 4] if v % 3 == 0 else rnd.between(-1, 1)
        struct.pack_into('<4f', b, 0, rnd.between(-spread, spread), rnd.between(-spread, spread),
                         rnd.between(-spread, spread), bx)
        if attrs & 0x2:
            b[off(2):off(2) + 4] = half(rnd.between(-1, 2)) + half(rnd.between(-1, 2))
        if attrs & 0x8:
            n = axes[v % 6] if axis_normals and v % 2 == 0 else (rnd.below(256), rnd.below(256), rnd.below(256))
            b[off(4):off(4) + 4] = bytes(n) + bytes([(127, 128, 0, 255)[v % 4] if v % 2 else rnd.below(256)])
        if attrs & 0x10:
            tt = axes[(v + 2) % 6] if axis_normals and v % 2 == 0 else (rnd.below(256), rnd.below(256), rnd.below(256))
            b[off(5):off(5) + 4] = bytes(tt) + bytes([rnd.below(256)])
        if attrs & 0x20:
            b[off(6):off(6) + 4] = rnd.raw(4)
        raw += b
    tris = b''.join(struct.pack('<3H', rnd.below(nv), rnd.below(nv), rnd.below(nv)) for _ in range(ntri))
    body = (nif.av(name, flags, t, rot, sc, extra=extra) + struct.pack('<4f', 1, 2, 3, 4) +
            struct.pack('<iiiQHHI', -1, shader, alpha, desc, ntri, nv, len(raw) + len(tris)) + bytes(raw) + tris +
            struct.pack('<I', 0))
    return nif.add('BSTriShape', body)


def material(nif, rnd, paths, extras=0, controller=-1):
    ts = nif.add('BSShaderTextureSet', struct.pack('<I', len(paths)) +
                 b''.join(struct.pack('<I', len(p)) + p.encode('ascii') for p in paths))
    ex = [nif.add('NiStringExtraData', rnd.raw(8)) for _ in range(extras)]
    rest = bytearray(rnd.raw(24)) + struct.pack('<i', ts) + rnd.raw(64)
    sh = nif.add('BSLightingShaderProperty', struct.pack('<I', rnd.below(20)) +
                 struct.pack('<iI', nif.string('shader%d' % len(nif.blocks)), len(ex)) +
                 b''.join(struct.pack('<i', e) for e in ex) + struct.pack('<i', controller) + bytes(rest))
    return sh


def alpha_block(nif, rnd):
    return nif.add('NiAlphaProperty', struct.pack('<iIiHB', -1, 0, -1, 4845 + rnd.below(100), rnd.below(256)))


def tex(n, rnd):
    base = ['textures\\fixture\\%s.dds' % n, 'textures\\fixture\\%s_n.dds' % n, '', '', '', '', '', '', '']
    return base


TEXTURES = set()


def textures(paths):
    for p in paths:
        if p:
            TEXTURES.add(p if p.lower().startswith('textures\\') else 'textures\\' + p)
    return paths


def simple(rnd, name, nshapes=1, **kw):
    """A mesh of a root and some shapes under it."""
    n = Nif()
    root = n.add('BSFadeNode')
    kids = []
    for k in range(nshapes):
        sh = material(n, rnd, textures(tex('%s%d' % (name, k), rnd)))
        kids.append(shape_block(n, rnd, '%s:%d' % (name, k), kw.get('desc', desc_of()), 7 + rnd.below(20),
                                3 + rnd.below(12), sh, axis_normals=True))
    n.node(root, 'BSFadeNode', name, 524302, (0, 0, 0), IDENT, 1.0, kids)
    return n


def rigid(n, rnd, shape_ref):
    return n.add('bhkRigidBody', struct.pack('<i', shape_ref) + rnd.raw(236))


def meshes(rnd):
    out = {}
    # posts: a turned and scaled node holding a shape with alpha and a hidden one, and a static body
    n = Nif()
    root = n.add('BSFadeNode')
    inner = n.add('NiNode')
    sh = material(n, rnd, textures(tex('post', rnd)), extras=2, controller=7)
    a = shape_block(n, rnd, 'Post', desc_of(), 24, 20, sh, alpha=alpha_block(n, rnd), t=(1.5, -2.25, 3.0),
                    rot=turn(0, 0, 90), sc=1.25, extra=(1, 2), axis_normals=True)
    hid = shape_block(n, rnd, 'Hidden', desc_of(), 5, 2, sh, flags=524303)
    n.node(inner, 'NiNode', 'Turned', 14, (10.0, 0.5, -4.0), turn(90, 0, 0), 1.1, [a, -1, hid])
    cv = n.add('bhkConvexVerticesShape', struct.pack('<I', 0xAABBCCDD) + rnd.raw(60))
    body = rigid(n, rnd, cv)
    col = n.add('bhkCollisionObject', struct.pack('<iHi', root, 0x81, body))
    n.node(root, 'BSFadeNode', 'SignPost', 524302, (0, 0, 0), IDENT, 1.0, [inner], collision=col)
    out['meshes\\clutter\\signage\\windhelm\\signwhpost01.nif'] = n
    # the board face: a node kind the build skips, holding a shape that must not appear
    n = Nif()
    root = n.add('BSFadeNode')
    skip = n.add('NiBillboardNode')
    sh = material(n, rnd, textures(tex('planks', rnd)))
    s1 = shape_block(n, rnd, 'Planks', desc_of(colour=False), 30, 28, sh, axis_normals=True, rot=turn(0, 30, 0))
    s2 = shape_block(n, rnd, 'NotSeen', desc_of(), 6, 2, sh)
    n.blocks[skip] = ['NiBillboardNode', n.av('Bill', 14, (0, 0, 0), IDENT, 1.0) + struct.pack('<Ii', 1, s2) +
                      struct.pack('<I', 0)]
    n.node(root, 'BSFadeNode', 'Wall', 524302, (0, 0, 0), IDENT, 1.0, [s1, skip])
    out['meshes\\clutter\\stockade\\stockadefreewall01.nif'] = n
    # the beam: nodes inside nodes, each turned and scaled
    n = Nif()
    root = n.add('BSFadeNode')
    a, b = n.add('NiNode'), n.add('BSValueNode')
    sh = material(n, rnd, textures(tex('beam', rnd)))
    s = shape_block(n, rnd, 'Beam', desc_of(tangent=False), 18, 14, sh, t=(0.0, 0.0, 6.5), rot=turn(-45, 0, 7),
                    sc=0.8, axis_normals=True)
    n.node(b, 'BSValueNode', 'Inner', 14, (2.0, -3.0, 1.0), turn(0, 90, 0), 1.5, [s])
    n.node(a, 'NiNode', 'Outer', 14, (-5.0, 0.0, 12.0), turn(0, 0, 180), 0.5, [b])
    n.node(root, 'BSFadeNode', 'Beam', 524302, (0, 0, 0), IDENT, 1.0, [a])
    out['meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif'] = n
    # the roof: a hidden node, which hides what it holds
    n = Nif()
    root = n.add('BSFadeNode')
    hidden = n.add('NiNode')
    sh = material(n, rnd, textures(tex('roof', rnd)))
    s1 = shape_block(n, rnd, 'Roof', desc_of(), 22, 16, sh, rot=turn(12, -45, 0), axis_normals=True)
    s2 = shape_block(n, rnd, 'UnderHidden', desc_of(), 6, 2, sh)
    n.node(hidden, 'NiNode', 'Hide', 15, (0, 0, 0), IDENT, 1.0, [s2])
    n.node(root, 'BSFadeNode', 'Roof', 524302, (0, 0, 0), IDENT, 1.0, [hidden, s1])
    out['meshes\\architecture\\shackkit\\shackroofside01.nif'] = n
    out['meshes\\clutter\\common\\candlelanternwithcandle01.nif'] = simple(rnd, 'Lantern', 2)
    for k, note in enumerate(['note01', 'note02', 'note03', 'note04', 'notetornpaper']):
        out['meshes\\clutter\\books\\%s.nif' % note] = simple(rnd, 'Note%d' % k, 1 + k % 2)
    out['meshes\\clutter\\shipwreck\\shipwreckboards01.nif'] = simple(rnd, 'Shelf', 1, desc=desc_of(uv=True, colour=False))
    # the strongbox: two shapes, a convex shape (its material) and a static body
    n = simple(rnd, 'Strongbox', 2)
    cv = n.add('bhkConvexVerticesShape', struct.pack('<I', 0x11223344) + rnd.raw(60))
    rigid(n, rnd, cv)
    out['meshes\\clutter\\common\\strongbox01.nif'] = n
    # the nail heads' source: the nail sheet named in capitals, on the third shape
    n = Nif()
    root = n.add('BSFadeNode')
    kids = []
    for k, paths in enumerate([tex('stall', rnd), tex('awning', rnd),
                               ['textures\\architecture\\solitude\\SNail01.dds', 'architecture\\solitude\\snail01_n.dds',
                                '', '', '', '', '', '', '']]):
        sh = material(n, rnd, textures(paths))
        kids.append(shape_block(n, rnd, 'Stall%d' % k, desc_of(), 9, 6, sh))
    n.node(root, 'BSFadeNode', 'Stall', 524302, (0, 0, 0), IDENT, 1.0, kids)
    out['meshes\\architecture\\solitude\\clutter\\smarketstalltop.nif'] = n
    return out


# ------------------------------------------------------------------------ SWF --
def swf_plain(rnd, edited):
    """An uncompressed SWF of a few hundred tags, much of it repeated (so the
    compression finds long and far matches). With edited, a few shapes change
    the way Thornswood's menu did: a byte or two each, and lengths with them."""
    tags = []
    for i in range(420):
        code = (2, 22, 26, 12, 39, 1, 88)[i % 7]
        size = (12, 40, 9, 300, 64, 0, 5000)[rnd.below(7)] + rnd.below(30) + (20 if code == 2 else 0)
        if i % 11 == 0:
            body = (b'Thornswood fixture %d ' % (i % 5)) * (size // 20 + 1)
        else:
            body = rnd.raw(size // 3) + bytes(size - size // 3)
        tags.append([code, bytearray(body[:size])])
    if edited:
        for i in (2, 9, 30, 72, 191):
            code, body = tags[i * 7 % 420]  # every seventh tag is a DefineShape
            body[3] ^= 0x5A
            del body[5:7]
            body[1:1] = b'\x01'
    out = bytearray()
    rect = bytes([0x78, 0x00, 0x05, 0x5F, 0x00, 0x00, 0x0F, 0xA0, 0x00])
    out += rect + struct.pack('<HH', 0x1E00, 1)
    for code, body in tags:
        if len(body) < 0x3F and code not in (2, 22):
            out += struct.pack('<H', (code << 6) | len(body))
        else:
            out += struct.pack('<HI', (code << 6) | 0x3F, len(body))
        out += body
    out += struct.pack('<H', 0)
    return b'FWS' + bytes([15]) + struct.pack('<I', 8 + len(out)) + bytes(out)


def stored_zlib(b):
    """A zlib stream of stored blocks, written here, so the game's menu in the
    archive is the same bytes whatever zlib this Python has."""
    out = bytearray(b'\x78\x01')
    for at in range(0, len(b), 65535):
        chunk = b[at:at + 65535]
        last = at + 65535 >= len(b)
        out += bytes([1 if last else 0]) + struct.pack('<HH', len(chunk), len(chunk) ^ 0xFFFF) + chunk
    a, s = 1, 0
    for x in b:
        a = (a + x) % 65521
        s = (s + a) % 65521
    return bytes(out) + struct.pack('>I', (s << 16) | a)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    rnd = Numbers(2827)
    m = {p: n.bytes() for p, n in meshes(rnd).items()}
    changed = '--changed' in sys.argv
    if changed:
        # the last triangle's last index, which the build copies as it is
        b = bytearray(m['meshes\\clutter\\books\\note01.nif'])
        b[-14] ^= 1
        m['meshes\\clutter\\books\\note01.nif'] = bytes(b)
    split = lambda p: (p.rsplit('\\', 1)[0], p.rsplit('\\', 1)[1])
    first = [p for p in sorted(m) if 'books' not in p]
    second = [p for p in sorted(m) if 'books' in p or 'strongbox' in p]
    # the first archive packs by default; the second does not, and names each file before its data
    other = Nif()
    r2 = other.add('BSFadeNode')
    other.node(r2, 'BSFadeNode', 'NotThisOne', 0, (0, 0, 0), IDENT, 1.0, [])
    files0 = [(split(p)[0].replace('clutter\\common', 'Clutter\\Common'), split(p)[1], m[p]) for p in first]
    files1 = [(split(p)[0], split(p)[1], other.bytes() if 'strongbox' in p else m[p]) for p in second]
    archive(os.path.join(out, 'Skyrim - Meshes0.bsa'), files0, compressed=True,
            toggle={'meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif'},
            frames={'meshes\\clutter\\signage\\windhelm\\signwhpost01.nif': dict(block_sums=True, content=True),
                    'meshes\\architecture\\shackkit\\shackroofside01.nif': dict(block=256, raw_first=True)})
    archive(os.path.join(out, 'Skyrim - Meshes1.bsa'), files1, embed=True,
            toggle={'meshes\\clutter\\books\\note02.nif', 'meshes\\clutter\\books\\notetornpaper.nif'})
    tex_files = sorted(TEXTURES)
    for i in range(9):
        mine = [(split(p)[0], split(p)[1], b'DDS ' + bytes([i])) for k, p in enumerate(tex_files) if k % 9 == i]
        archive(os.path.join(out, 'Skyrim - Textures%d.bsa' % i), mine, compressed=i % 2 == 1)
    plain = swf_plain(Numbers(1177), False)
    game_swf = b'CWS' + plain[3:8] + stored_zlib(plain[8:])
    if changed:
        game_swf = game_swf[:5000] + bytes([game_swf[5000] ^ 1]) + game_swf[5001:]
    archive(os.path.join(out, 'Skyrim - Interface.bsa'),
            [('interface', 'fontconfig.txt', b'fixture'), ('interface', 'startmenu.swf', game_swf)],
            compressed=True, embed=True, frames={'interface\\startmenu.swf': dict(block_sums=True)})
    if '--edited' in sys.argv:
        import zlib
        edited = swf_plain(Numbers(1177), True)
        c = zlib.compressobj(6, zlib.DEFLATED, 15, 8, zlib.Z_DEFAULT_STRATEGY)
        with open(os.path.join(out, 'edited-startmenu.swf'), 'wb') as f:
            f.write(b'CWS' + edited[3:8] + c.compress(edited[8:]) + c.flush())
    print('wrote the made-up game in ' + out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
