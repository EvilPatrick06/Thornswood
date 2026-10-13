"""
Build-NoticeBoard.py

Builds the notice board and its drop box, Thornswood's own two meshes, from
Skyrim's own vanilla meshes and textures (#2298):

    game\\ours\\Data\\meshes\\thornswood\\noticeboard01.nif
    game\\ours\\Data\\meshes\\thornswood\\dropbox01.nif

WHY

Until 12 Oct the board's mesh was a reworked copy of the board in Missives
(Nexus 111375), which came with the other server's records and whose
permissions nobody had read (#1258, #2298). Patrick chose our own board made
of vanilla pieces, approved the concept with the hold's drop box on a shelf
on its right post (concept-a-dropbox, 12 Oct), and then said to build it.

WHAT IS IN THEM

Every shape is a vanilla shape read out of the game's own archives, with its
vanilla shader and its vanilla texture paths, so no texture ships:

    posts           meshes\\clutter\\signage\\windhelm\\signwhpost01.nif
    board face      meshes\\clutter\\stockade\\stockadefreewall01.nif
    rails, bracket,
    shelf strut     meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif
    roof            meshes\\architecture\\shackkit\\shackroofside01.nif (two)
    lantern         meshes\\clutter\\common\\candlelanternwithcandle01.nif
    notices         meshes\\clutter\\books\\note01..04.nif, notetornpaper.nif
    box shelf       meshes\\clutter\\shipwreck\\shipwreckboards01.nif
    the drop box    meshes\\clutter\\common\\strongbox01.nif, scaled 1.8

Three small pieces have no vanilla mesh and are made here: a nail head on each
notice (textured with Solitude's nail sheet, snail01.dds), and the box's coin
slot and its iron lip (the strongbox's own texture). Nothing comes from
Missives.

Each part is placed where PARTS says (position, rotation in degrees about x, y
and z, scale per axis), and baked: its vertices, normals and tangents are moved
into the root's space, because a NIF transform cannot hold the non-uniform
scales the concept used. Both meshes face +y, the way the board they replace
faced, so the spots the client already puts boards at keep working. The
board's origin is on the ground in the middle of the board; the box's is the
bottom middle of the box, which stands BOX_OFFSET from the board's origin in
the board's own space (the gamemode places it there, turned with the board).

COLLISION, AND PATRICK'S CLICK RULE

Patrick, 12 Oct: clicking the board does only the board and clicking the drop
box does only the box. So each mesh has its own Havok collision: a static body
(a vanilla static body's settings, layer STATIC) with one convex box per part.
The board's boxes cover its posts, face, rails, roof, lantern and bracket, and
the shelf and strut the box stands on, and none of them reaches over the box;
the box's one covers only the box. Notices have none of their own: a click on
a notice lands on the face behind it, which is the board.

Collision cannot be tried without the game: the in game check is in the
issue's test task.

Usage, on a machine with the game (the archives are read, never written):
    python scripts/mods/Build-NoticeBoard.py           build and write both
    python scripts/mods/Build-NoticeBoard.py --check   build in memory and say
                                                      whether the files in the
                                                      repo are those bytes
    --data <the game's Data folder>, default C:\\Thornswood\\Game\\Data
Exit 1 when a check fails or a vanilla part cannot be read.
"""

import argparse
import os
import struct
import sys

import lz4.frame
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(REPO, 'game', 'ours', 'Data', 'meshes', 'thornswood')
DATA = 'C:\\Thornswood\\Game\\Data'
ARCHIVES = (['Skyrim - Meshes0.bsa', 'Skyrim - Meshes1.bsa'] +
            ['Skyrim - Textures%d.bsa' % i for i in range(9)])

HAVOK = 69.99125      # game units to one Havok unit, Skyrim's
WOOD = 0x1DD9C611     # the Havok material vanilla wood uses
TURN = np.diag([-1.0, -1.0, 1.0])  # the concept faced -y; the game's board faces +y

POST = 'meshes\\clutter\\signage\\windhelm\\signwhpost01.nif'
PLANKS = 'meshes\\clutter\\stockade\\stockadefreewall01.nif'
BEAM = 'meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif'
ROOF = 'meshes\\architecture\\shackkit\\shackroofside01.nif'
LANTERN = 'meshes\\clutter\\common\\candlelanternwithcandle01.nif'
SHELF = 'meshes\\clutter\\shipwreck\\shipwreckboards01.nif'
STRONGBOX = 'meshes\\clutter\\common\\strongbox01.nif'
NAIL_SOURCE = 'meshes\\architecture\\solitude\\clutter\\smarketstalltop.nif'
BODY_BOARD = POST        # whose static body settings the board's collision uses
BODY_BOX = STRONGBOX     # and the box's, with the strongbox's own material

NAIL_UV = (0.335, 0.375, 0.442, 0.488)  # the plain square nail head on snail01.dds
LIP_UV = (0.02, 0.905, 0.98, 0.995)     # the iron braid along the bottom of strongbox.dds
VERTEX_DESC = 0x3B00007650408           # position, uv, normal, tangent, colour: vanilla's

# (name, mesh, rotation x y z, scale x y z, position x y z), in the concept's space
# (the board facing -y, the ground at z 0). Read off the approved concept sheet.
PARTS = [
    ('Post', POST, (0, 0, 0), (1.05, 1.05, 1.18), (-92.0, 0.0, 0.0)),
    ('Post', POST, (0, 0, 0), (1.05, 1.05, 1.18), (92.0, 0.0, 0.0)),
    ('Face', PLANKS, (0, 0, 0), (0.7, 0.7, 0.7), (-90.4146, 3.6651, 53.9283)),
    ('TopRail', BEAM, (0, 0, 90), (0.95, 1.4, 0.95), (0.0, -11.6461, 187.876)),
    ('BottomRail', BEAM, (0, 0, 90), (0.95, 1.4, 0.95), (0.0, -11.6461, 56.0)),
    ('Roof', ROOF, (0, 0, 180), (0.86, 0.52, 0.4), (0.0, -1.8538, 116.9737)),
    ('Roof', ROOF, (0, 0, 0), (0.86, 0.52, 0.4), (0.0, 1.8538, 116.9737)),
    ('LanternBracket', BEAM, (0, 0, 90), (0.55, 0.36, 0.55), (-113.8082, 0.0, 206.0)),
    ('Lantern', LANTERN, (0, 0, 0), (1.0, 1.0, 1.0), (-130.6979, 0.2446, 159.4178)),
    ('Note', 'meshes\\clutter\\books\\note01.nif', (90, -4, 0), (2.2, 2.2, 2.2), (-56.8055, -0.3503, 146.2702)),
    ('Note', 'meshes\\clutter\\books\\notetornpaper.nif', (90, 3, 0), (2.2, 2.2, 2.2), (-21.4435, -1.3009, 135.9732)),
    ('Note', 'meshes\\clutter\\books\\note02.nif', (90, -2, 0), (2.2, 2.2, 2.2), (15.5093, -0.6503, 148.3532)),
    ('Note', 'meshes\\clutter\\books\\note04.nif', (90, 5, 0), (2.2, 2.2, 2.2), (55.4836, -0.8003, 139.9631)),
    ('Note', 'meshes\\clutter\\books\\note03.nif', (90, 2, 0), (2.2, 2.2, 2.2), (-52.3024, -0.9503, 93.395)),
    ('Note', 'meshes\\clutter\\books\\notetornpaper.nif', (90, -3, 0), (2.2, 2.2, 2.2), (-12.6061, -1.9009, 96.4548)),
    ('Note', 'meshes\\clutter\\books\\note01.nif', (90, 4, 0), (2.2, 2.2, 2.2), (24.6941, -1.2503, 93.3798)),
    ('Note', 'meshes\\clutter\\books\\note02.nif', (90, -3, 0), (2.2, 2.2, 2.2), (60.1875, -1.4003, 96.4912)),
    ('BoxShelf', SHELF, (0, 0, 90), (3.4, 0.36, 1.6), (132.5203, -4.0, 76.8)),
    ('Strut', BEAM, (-45, 0, 90), (0.45, 0.36, 0.45), (117.3618, -4.0, 54.2656)),
]
BOX = ('DropBox', STRONGBOX, (0, 0, 0), (1.8, 1.8, 1.8), (134.5203, -4.0, 79.9167))
# The parts whose collision lies along their own slant; every other part's is square to the board.
SLANTED = ('Roof', 'Strut')


# ------------------------------------------------------------------ archives --
class Archive(object):
    """Skyrim SE BSA (version 105), read only."""

    def __init__(self, path):
        self.path, self.files = path, {}
        with open(path, 'rb') as f:
            magic, ver, foff, flags, nfold, nfile, lfold, lfile, _ = struct.unpack('<4sIIIIIIIH', f.read(34))
            if magic != b'BSA\0' or ver != 105:
                raise SystemExit('STOP. %s is not a Skyrim SE archive.' % path)
            self.compressed, self.embed = bool(flags & 0x4), bool(flags & 0x100)
            f.seek(foff)
            counts = [struct.unpack('<QIIQ', f.read(24))[1] for _ in range(nfold)]
            recs = []
            for cnt in counts:
                n = f.read(1)[0]
                folder = f.read(n)[:-1].decode('cp1252')
                for _ in range(cnt):
                    _, size, off = struct.unpack('<QII', f.read(16))
                    recs.append((folder, size, off))
            names = f.read(lfile).split(b'\0')
            for (folder, size, off), name in zip(recs, names):
                self.files[(folder + '\\' + name.decode('cp1252')).lower()] = (size, off)

    def read(self, p):
        size, off = self.files[p]
        packed = self.compressed ^ bool(size & 0x40000000)
        size &= 0x3FFFFFFF
        with open(self.path, 'rb') as f:
            f.seek(off)
            if self.embed:
                n = f.read(1)[0]
                f.read(n)
                size -= n + 1
            if packed:
                f.read(4)
                return lz4.frame.decompress(f.read(size - 4))
            return f.read(size)


class Vanilla(object):
    def __init__(self, data):
        self.archives = []
        for name in ARCHIVES:
            path = os.path.join(data, name)
            if not os.path.isfile(path):
                raise SystemExit('STOP. %s is not in %s. Give --data the game\'s Data folder.' % (name, data))
            self.archives.append((name, Archive(path)))

    def find(self, p):
        p = p.lower().replace('/', '\\')
        for name, a in self.archives:
            if p in a.files:
                return name, a
        return None, None

    def read(self, p):
        name, a = self.find(p)
        if a is None:
            raise SystemExit('STOP. %s is not in the vanilla archives.' % p)
        return a.read(p.lower().replace('/', '\\'))


# ---------------------------------------------------------------- nif reader --
class Reader(object):
    def __init__(self, b, o=0):
        self.b, self.o = b, o

    def take(self, fmt):
        v = struct.unpack_from('<' + fmt, self.b, self.o)
        self.o += struct.calcsize('<' + fmt)
        return v if len(v) > 1 else v[0]

    def sized(self):
        n = self.take('I')
        s = self.b[self.o:self.o + n].decode('cp1252')
        self.o += n
        return s


NODES = ('NiNode', 'BSFadeNode', 'BSValueNode', 'BSLeafAnimNode', 'BSMultiBoundNode', 'BSOrderedNode')


class Nif(object):
    """Enough of a Skyrim SE NIF to copy its shapes: the node tree, each
    BSTriShape's vertex data, and its shader and texture set blocks."""

    def __init__(self, data):
        r = Reader(data)
        r.o = data.index(b'\n') + 1
        version, _, user, count = r.take('IBII')
        self.bsver = r.take('I')
        if (version, user, self.bsver) != (0x14020007, 12, 100):
            raise SystemExit('STOP. not a Skyrim SE NIF.')
        for _ in range(3):
            r.o += 1 + data[r.o]
        types = [r.sized() for _ in range(r.take('H'))]
        kinds = [types[r.take('H') & 0x7FFF] for _ in range(count)]
        sizes = [r.take('I') for _ in range(count)]
        nstr = r.take('I')
        r.take('I')
        self.strings = [r.sized() for _ in range(nstr)]
        groups = r.take('I')
        r.o += 4 * groups
        self.data, self.blocks = data, []
        for k, s in zip(kinds, sizes):
            self.blocks.append((k, r.o, s))
            r.o += s

    def block(self, i):
        t, o, s = self.blocks[i]
        return t, self.data[o:o + s]

    def av(self, r):
        name = r.take('i')
        extra = r.take('I')
        r.o += 4 * extra
        r.take('i')
        flags = r.take('I')
        t = np.array(r.take('3f'))
        rot = np.array(r.take('9f')).reshape(3, 3)
        sc = r.take('f')
        r.take('i')
        return name, flags, t, rot, sc

    def texture(self, shader):
        t, b = self.block(shader)
        nextra = struct.unpack_from('<I', b, 8)[0]
        ts = struct.unpack_from('<i', b, 12 + 4 * nextra + 4 + 24)[0]
        tt, tb = self.block(ts)
        if tt != 'BSShaderTextureSet':
            raise SystemExit('STOP. a shader that does not name a texture set.')
        r = Reader(tb)
        n = r.take('I')
        paths = [r.sized() for _ in range(n)]
        return b, tb, paths

    def shapes(self):
        out = []

        def walk(i, M, T, S):
            t, o, size = self.blocks[i]
            r = Reader(self.data, o)
            if t in NODES:
                name, flags, tr, rot, sc = self.av(r)
                if flags & 1:
                    return
                M2, T2, S2 = M @ rot.T, T + S * (M @ tr), S * sc
                for _ in range(r.take('I')):
                    k = r.take('i')
                    if k >= 0:
                        walk(k, M2, T2, S2)
            elif t == 'BSTriShape':
                name, flags, tr, rot, sc = self.av(r)
                if flags & 1:
                    return
                r.take('4f')
                _, shader, alpha = r.take('iii')
                desc = r.take('Q')
                ntri, nv, _ = r.take('HHI')
                vsize = (desc & 0xF) * 4
                raw = np.frombuffer(self.data, np.uint8, nv * vsize, r.o).reshape(nv, vsize)
                r.o += nv * vsize
                tris = np.frombuffer(self.data, np.uint16, ntri * 3, r.o).reshape(ntri, 3).astype(np.int64)
                al = None
                if alpha >= 0:
                    _, ab = self.block(alpha)
                    al = struct.unpack_from('<HB', ab, 12)
                sh, ts, paths = self.texture(shader)
                out.append(dict(name=self.strings[name] if name >= 0 else '', flags=flags, desc=desc,
                                raw=raw, tris=tris, alpha=al, shader=sh, texset=ts, paths=paths,
                                M=M @ rot.T, S=S * sc, T=T + S * (M @ tr)))

        walk(0, np.eye(3), np.zeros(3), 1.0)
        return out


def unpack(s):
    raw, desc = s['raw'], s['desc']
    nv = len(raw)
    attrs = (desc >> 44) & 0xFFF
    off = lambda k: ((desc >> (4 * k)) & 0xF) * 4
    p = raw[:, 0:16].copy().view(np.float32).reshape(nv, 4).astype(float)
    ints = raw.astype(float)
    bit = np.zeros((nv, 3)); bit[:, 0] = p[:, 3]
    uv = np.zeros((nv, 2)); nrm = np.zeros((nv, 3)); tan = np.zeros((nv, 3)); col = np.ones((nv, 4))
    if attrs & 0x2:
        o = off(2); uv = raw[:, o:o + 4].copy().view(np.float16).reshape(nv, 2).astype(float)
    if attrs & 0x8:
        o = off(4); nrm = ints[:, o:o + 3] / 127.5 - 1.0; bit[:, 1] = ints[:, o + 3] / 127.5 - 1.0
    if attrs & 0x10:
        o = off(5); tan = ints[:, o:o + 3] / 127.5 - 1.0; bit[:, 2] = ints[:, o + 3] / 127.5 - 1.0
    if attrs & 0x20:
        o = off(6); col = ints[:, o:o + 4] / 255.0
    return p[:, :3], uv, nrm, tan, bit, col


# ---------------------------------------------------------------- nif writer --
def short(s):
    b = s.encode('ascii') + b'\0'
    return struct.pack('<B', len(b)) + b


def sized(s):
    b = s.encode('ascii')
    return struct.pack('<I', len(b)) + b


IDENT = struct.pack('<12f', 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1) + struct.pack('<f', 1.0)
AV_FLAGS = 524302  # the flags vanilla static shapes and roots carry


def av_object(name, flags, extra=(), collision=-1):
    b = struct.pack('<iI', name, len(extra)) + b''.join(struct.pack('<i', e) for e in extra)
    return b + struct.pack('<iI', -1, flags) + IDENT + struct.pack('<i', collision)


def unit(v):
    n = np.linalg.norm(v, axis=1, keepdims=True)
    return np.where(n > 1e-9, v / np.maximum(n, 1e-9), v)


def to_byte(v):
    return np.clip(np.round((v + 1.0) * 127.5), 0, 255).astype(np.uint8)


def vertices(desc, pos, uv, nrm, tan, bit, col):
    nv = len(pos)
    vsize = (desc & 0xF) * 4
    attrs = (desc >> 44) & 0xFFF
    off = lambda k: ((desc >> (4 * k)) & 0xF) * 4
    raw = np.zeros((nv, vsize), np.uint8)
    p = np.zeros((nv, 4), np.float32)
    p[:, :3] = pos
    p[:, 3] = bit[:, 0]
    raw[:, 0:16] = p.view(np.uint8).reshape(nv, 16)
    if attrs & 0x2:
        o = off(2); raw[:, o:o + 4] = uv.astype(np.float16).view(np.uint8).reshape(nv, 4)
    if attrs & 0x8:
        o = off(4); raw[:, o:o + 3] = to_byte(nrm); raw[:, o + 3] = to_byte(bit[:, 1])
    if attrs & 0x10:
        o = off(5); raw[:, o:o + 3] = to_byte(tan); raw[:, o + 3] = to_byte(bit[:, 2])
    if attrs & 0x20:
        o = off(6); raw[:, o:o + 4] = np.clip(np.round(col * 255), 0, 255).astype(np.uint8)
    return raw.tobytes()


def shader_copy(src, texset, vertex_colours=False):
    """A vanilla BSLightingShaderProperty with no name, extra data or controller,
    pointing at texset."""
    nextra = struct.unpack_from('<I', src, 8)[0]
    rest = bytearray(src[12 + 4 * nextra + 4:])
    struct.pack_into('<i', rest, 24, texset)
    if vertex_colours:
        f2 = struct.unpack_from('<I', rest, 4)[0]
        struct.pack_into('<I', rest, 4, f2 | 0x20)
    return src[:4] + struct.pack('<iIi', -1, 0, -1) + bytes(rest)


class Mesh(object):
    def __init__(self, root_name):
        self.blocks, self.strings = [], []
        self.root = self.add('BSFadeNode', b'')
        self.bsx = self.add('BSXFlags', struct.pack('<iI', self.string('BSX'), 130))
        self.root_name, self.kids, self.hulls, self.points, self.triangles = root_name, [], [], [], 0

    def string(self, s):
        if s not in self.strings:
            self.strings.append(s)
        return self.strings.index(s)

    def add(self, kind, body):
        self.blocks.append([kind, body])
        return len(self.blocks) - 1

    def shape(self, name, flags, desc, geom, shader, texset, alpha=None, vertex_colours=False):
        pos, uv, nrm, tan, bit, col, tris = geom
        ts = self.add('BSShaderTextureSet', texset)
        sh = self.add('BSLightingShaderProperty', shader_copy(shader, ts, vertex_colours))
        al = -1
        if alpha is not None:
            al = self.add('NiAlphaProperty', struct.pack('<iIiHB', -1, 0, -1, alpha[0], alpha[1]))
        c = (pos.min(0) + pos.max(0)) / 2
        rad = float(np.sqrt(((pos - c) ** 2).sum(1)).max())
        vb = vertices(desc, pos, uv, nrm, tan, bit, col)
        tb = np.asarray(tris, np.uint16).tobytes()
        body = (av_object(self.string(name), flags) + struct.pack('<4f', c[0], c[1], c[2], rad) +
                struct.pack('<iiiQHHI', -1, sh, al, desc, len(tris), len(pos), len(vb) + len(tb)) +
                vb + tb + struct.pack('<I', 0))
        self.kids.append(self.add('BSTriShape', body))
        self.points.append(pos)
        self.triangles += len(tris)

    def finish(self, body_template, material):
        subs = [self.add('bhkConvexVerticesShape', convex(h, material)) for h in self.hulls]
        if len(subs) == 1:
            shape = subs[0]
        else:
            shape = self.add('bhkListShape', struct.pack('<I', len(subs)) +
                             b''.join(struct.pack('<i', s) for s in subs) + struct.pack('<I', material) +
                             struct.pack('<6I', 0, 0, 0x80000000, 0, 0, 0x80000000) +
                             struct.pack('<I', len(subs)) + b'\0' * (4 * len(subs)))
        rb = bytearray(body_template)
        struct.pack_into('<i', rb, 0, shape)
        body = self.add('bhkRigidBody', bytes(rb))
        col = self.add('bhkCollisionObject', struct.pack('<iHi', self.root, 0x81, body))
        self.blocks[self.root][1] = (av_object(self.string(self.root_name), AV_FLAGS, [self.bsx], col) +
                                     struct.pack('<I', len(self.kids)) +
                                     b''.join(struct.pack('<i', k) for k in self.kids) + struct.pack('<I', 0))
        kinds = []
        for k, _ in self.blocks:
            if k not in kinds:
                kinds.append(k)
        out = b'Gamebryo File Format, Version 20.2.0.7\n'
        out += struct.pack('<IBIII', 0x14020007, 1, 12, len(self.blocks), 100)
        out += short('Thornswood') + short('') + short('')
        out += struct.pack('<H', len(kinds)) + b''.join(sized(k) for k in kinds)
        out += b''.join(struct.pack('<H', kinds.index(k)) for k, _ in self.blocks)
        out += b''.join(struct.pack('<I', len(b)) for _, b in self.blocks)
        out += struct.pack('<II', len(self.strings), max(len(s) for s in self.strings))
        out += b''.join(sized(s) for s in self.strings) + struct.pack('<I', 0)
        out += b''.join(b for _, b in self.blocks) + struct.pack('<Ii', 1, 0)
        return out


def corners(lo, hi, axes=np.eye(3), centre=np.zeros(3)):
    return np.array([centre + np.array([hi[0] if k & 1 else lo[0], hi[1] if k & 2 else lo[1],
                                        hi[2] if k & 4 else lo[2]]) @ axes for k in range(8)])


def square_box(P):
    return corners(P.min(0), P.max(0))


def slanted_box(P):
    """A box along the part's own axes: the principal axes of its points, snapped to
    the board's where they nearly are one."""
    c = P.mean(0)
    axes = np.linalg.svd(P - c, full_matrices=False)[2]
    for i in range(3):
        k = int(np.argmax(abs(axes[i])))
        if abs(axes[i][k]) > 0.995:
            a = np.zeros(3); a[k] = np.sign(axes[i][k]); axes[i] = a
    a0 = axes[0] / np.linalg.norm(axes[0])
    a1 = axes[1] - a0 * (axes[1] @ a0); a1 /= np.linalg.norm(a1)
    A = np.stack([a0, a1, np.cross(a0, a1)])
    loc = (P - c) @ A.T
    return corners(loc.min(0), loc.max(0), A, c)


def convex(box, material, radius=0.01):
    """bhkConvexVerticesShape for a box's 8 corners: the corners and the six outward
    planes (normal, w = -furthest), in Havok units."""
    v = np.asarray(box, float) / HAVOK
    planes = []
    for d in (v[1] - v[0], v[2] - v[0], v[4] - v[0]):
        n = d / np.linalg.norm(d)
        for nn in (n, -n):
            planes.append((nn[0], nn[1], nn[2], -float((v @ nn).max())))
    b = struct.pack('<If', material, radius) + struct.pack('<6I', 0, 0, 0x80000000, 0, 0, 0x80000000)
    b += struct.pack('<I', 8) + b''.join(struct.pack('<4f', x, y, z, 0.0) for x, y, z in v)
    b += struct.pack('<I', 6) + b''.join(struct.pack('<4f', *p) for p in planes)
    return b


def rotation(rx, ry, rz):
    rx, ry, rz = [np.radians(a) for a in (rx, ry, rz)]
    X = np.array([[1, 0, 0], [0, np.cos(rx), -np.sin(rx)], [0, np.sin(rx), np.cos(rx)]])
    Y = np.array([[np.cos(ry), 0, np.sin(ry)], [0, 1, 0], [-np.sin(ry), 0, np.cos(ry)]])
    Z = np.array([[np.cos(rz), -np.sin(rz), 0], [np.sin(rz), np.cos(rz), 0], [0, 0, 1]])
    return Z @ Y @ X


def baked(s, rot, scale, pos, shift):
    """One vanilla shape placed and moved into the built mesh's space."""
    A = TURN @ rotation(*rot) @ np.diag(scale) @ (s['S'] * s['M'])
    b = TURN @ (rotation(*rot) @ (np.array(scale) * s['T']) + np.array(pos)) + shift
    p, uv, nrm, tan, bit, col = unpack(s)
    return (p @ A.T + b, uv, unit(nrm @ np.linalg.inv(A)), unit(tan @ A.T), unit(bit @ A.T), col, s['tris'])


def flat_box(centre, size, uvr, colour=(1, 1, 1, 1)):
    """A small flat shaded box, every face mapped onto one rectangle of a texture."""
    c, h = np.asarray(centre, float), np.asarray(size, float) / 2
    faces = [((0, 0, 1), (1, 0, 0), (0, 1, 0)), ((0, 0, -1), (1, 0, 0), (0, -1, 0)),
             ((1, 0, 0), (0, 1, 0), (0, 0, 1)), ((-1, 0, 0), (0, -1, 0), (0, 0, 1)),
             ((0, 1, 0), (-1, 0, 0), (0, 0, 1)), ((0, -1, 0), (1, 0, 0), (0, 0, 1))]
    u0, v0, u1, v1 = uvr
    pos, uv, nrm, tan, bit, tris = [], [], [], [], [], []
    for n, t, bt in faces:
        n, t, bt = np.array(n, float), np.array(t, float), np.array(bt, float)
        base = len(pos)
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            pos.append(c + n * h + t * h * su * abs(t) + bt * h * sv * abs(bt))
            uv.append((u0 + (u1 - u0) * (su + 1) / 2, v1 - (v1 - v0) * (sv + 1) / 2))
            nrm.append(n); tan.append(t); bit.append(bt)
        tris += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    k = len(pos)
    return [np.array(pos), np.array(uv), np.array(nrm), np.array(tan), np.array(bit),
            np.tile(np.array(colour, float), (k, 1)), np.array(tris)]


def joined(geoms):
    out = [np.concatenate([g[i] for g in geoms]) for i in range(6)]
    tris, base = [], 0
    for g in geoms:
        tris.append(g[6] + base)
        base += len(g[0])
    return out + [np.concatenate(tris)]


def static_body(vanilla, path):
    n = Nif(vanilla.read(path))
    for k, o, s in n.blocks:
        if k == 'bhkRigidBody':
            return n.data[o:o + s]
    raise SystemExit('STOP. %s has no static body to take settings from.' % path)


def build(vanilla):
    cache = {}

    def shapes(path):
        if path not in cache:
            cache[path] = Nif(vanilla.read(path)).shapes()
        return cache[path]

    board = Mesh('ThornswoodNoticeBoard01')
    box = Mesh('ThornswoodDropBox01')
    zero = np.zeros(3)
    count = {}
    notes = []
    for name, path, rot, scale, pos in PARTS:
        count[name] = count.get(name, 0) + 1
        pts = []
        for k, s in enumerate(shapes(path)):
            g = baked(s, rot, scale, pos, zero)
            board.shape('%s%02d:%d' % (name, count[name], k), s['flags'], s['desc'], g,
                        s['shader'], s['texset'], s['alpha'])
            pts.append(g[0])
        P = np.concatenate(pts)
        if name == 'Note':
            notes.append(P)
        else:
            board.hulls.append(slanted_box(P) if name in SLANTED else square_box(P))

    # a nail head at the top middle of each notice, standing proud of the paper
    src = next(s for s in shapes(NAIL_SOURCE) if any('snail01' in p.lower() for p in s['paths']))
    heads = [flat_box(((P.min(0)[0] + P.max(0)[0]) / 2, P.max(0)[1] + 0.35, P.max(0)[2] - 2.6),
                      (2.4, 0.9, 2.4), NAIL_UV) for P in notes]
    board.shape('NailHeads', AV_FLAGS, VERTEX_DESC, joined(heads), src['shader'], src['texset'])

    # the drop box: the strongbox, its origin at the bottom middle of the box
    name, path, rot, scale, pos = BOX
    pts = [baked(s, rot, scale, pos, zero)[0] for s in shapes(path)]
    P = np.concatenate(pts)
    origin = np.array([(P.min(0)[0] + P.max(0)[0]) / 2, (P.min(0)[1] + P.max(0)[1]) / 2, P.min(0)[2]])
    for k, s in enumerate(shapes(path)):
        g = baked(s, rot, scale, pos, -origin)
        box.shape('%s:%d' % (name, k), s['flags'], s['desc'], g, s['shader'], s['texset'], s['alpha'])
    top = P.max(0)[2] - P.min(0)[2]
    sb = shapes(path)[0]
    box.shape('CoinSlotLip', AV_FLAGS, VERTEX_DESC, flat_box((0, 0, top - 0.2), (24.0, 10.5, 1.4), LIP_UV),
              sb['shader'], sb['texset'])
    box.shape('CoinSlot', AV_FLAGS, VERTEX_DESC,
              flat_box((0, 0, top + 0.52), (19.0, 3.6, 0.05), LIP_UV, (0.03, 0.03, 0.03, 1)),
              sb['shader'], sb['texset'], vertex_colours=True)
    box.hulls.append(square_box(np.concatenate(box.points)))

    n = Nif(vanilla.read(BODY_BOX))
    material = next(struct.unpack_from('<I', n.data, o)[0] for k, o, s in n.blocks if k == 'bhkConvexVerticesShape')
    board_bytes = board.finish(static_body(vanilla, BODY_BOARD), WOOD)
    box_bytes = box.finish(static_body(vanilla, BODY_BOX), material)
    return board_bytes, box_bytes, board, box, origin


def check_mesh(name, data, vanilla):
    """Every block reads to its size, every reference is to the right kind, and every
    texture is in the vanilla archives. Returns the problems found."""
    bad = []
    n = Nif(data)
    kinds = [k for k, o, s in n.blocks]
    last = n.blocks[-1]
    if struct.unpack_from('<Ii', data, last[1] + last[2]) != (1, 0) or last[1] + last[2] + 8 != len(data):
        bad.append(name + ': the footer is not one root at block 0 at the end of the file')
    for i, (k, o, s) in enumerate(n.blocks):
        b = data[o:o + s]
        if k == 'BSTriShape':
            r = Reader(data, o)
            n.av(r); r.take('4f')
            _, sh, al = r.take('iii'); desc = r.take('Q'); ntri, nv, size = r.take('HHI')
            if r.o + size + 4 != o + s or ntri * 6 + nv * (desc & 0xF) * 4 != size:
                bad.append('%s: shape %d does not read to its size' % (name, i))
            if kinds[sh] != 'BSLightingShaderProperty' or (al != -1 and kinds[al] != 'NiAlphaProperty'):
                bad.append('%s: shape %d names the wrong kind of block' % (name, i))
        elif k == 'BSShaderTextureSet':
            r = Reader(b)
            for p in [r.sized() for _ in range(r.take('I'))]:
                if p and vanilla.find(p if p.lower().startswith('textures\\') else 'textures\\' + p)[1] is None:
                    bad.append('%s: texture %s is not in the vanilla archives' % (name, p))
            if r.o != s:
                bad.append('%s: texture set %d does not read to its size' % (name, i))
        elif k == 'bhkConvexVerticesShape':
            r = Reader(b, 32)
            v = [r.take('4f') for _ in range(r.take('I'))]
            planes = [r.take('4f') for _ in range(r.take('I'))]
            if r.o != s or max(p[0] * q[0] + p[1] * q[1] + p[2] * q[2] + p[3] for p in planes for q in v) > 1e-4:
                bad.append('%s: convex shape %d is not a closed box' % (name, i))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=DATA)
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    vanilla = Vanilla(args.data)
    board_bytes, box_bytes, board, box, origin = build(vanilla)
    bad = check_mesh('noticeboard01.nif', board_bytes, vanilla) + check_mesh('dropbox01.nif', box_bytes, vanilla)
    allb = np.concatenate(board.points)
    print('noticeboard01.nif  %s bytes, %d triangles, %d collision boxes, from %s to %s'
          % (format(len(board_bytes), ','), board.triangles, len(board.hulls),
             allb.min(0).round(1).tolist(), allb.max(0).round(1).tolist()))
    print('dropbox01.nif      %s bytes, %d triangles, %d collision box'
          % (format(len(box_bytes), ','), box.triangles, len(box.hulls)))
    print('the box\'s origin stands at %s in the board\'s space; the gamemode places it there'
          % origin.round(2).tolist())
    for b in bad:
        print('  BAD  ' + b)
    if bad:
        return 1
    pairs = (('noticeboard01.nif', board_bytes), ('dropbox01.nif', box_bytes))
    if args.check:
        differ = [n for n, b in pairs
                  if not os.path.isfile(os.path.join(OUT, n)) or open(os.path.join(OUT, n), 'rb').read() != b]
        for n in differ:
            print('  DIFFERS  %s is not what this builds' % n)
        print('  ok    both files are what this builds' if not differ else '')
        return 1 if differ else 0
    os.makedirs(OUT, exist_ok=True)
    for n, b in pairs:
        open(os.path.join(OUT, n), 'wb').write(b)
        print('wrote ' + os.path.join(OUT, n))
    return 0


if __name__ == '__main__':
    sys.exit(main())
