"""Index every record and GRUP in a TES4 plugin, with byte ranges and parentage."""
import struct, zlib

HDR = 24
COMPRESSED = 0x00040000

def fields(d):
    off, out, x = 0, [], None
    while off + 6 <= len(d):
        t = d[off:off+4]; sz = struct.unpack_from('<H', d, off+4)[0]; off += 6
        if t == b'XXXX':
            x = struct.unpack_from('<I', d, off)[0]; off += sz; continue
        if x is not None: sz, x = x, None
        out.append((t, d[off:off+sz])); off += sz
    return out

def zstr(b): return b.split(b'\0')[0].decode('cp1252', 'replace')

class Node:
    __slots__ = ('kind','type','start','end','fid','flags','gtype','label','children','parent','body')
    def __init__(self, kind, **kw):
        self.kind = kind; self.children = []; self.parent = None; self.body = None
        for k, v in kw.items(): setattr(self, k, v)

def index(raw):
    root = Node('root', start=0, end=len(raw), type=b'ROOT', gtype=-1, label=0)
    recs = {}
    def walk(node, s, e):
        off = s
        while off + HDR <= e:
            rt = raw[off:off+4]
            if rt == b'GRUP':
                gs, label, gtype = struct.unpack_from('<IIi', raw, off+4)
                if gs < HDR: return
                g = Node('grup', type=rt, start=off, end=min(off+gs, e),
                         gtype=gtype, label=label, fid=None, flags=0)
                g.parent = node; node.children.append(g)
                walk(g, off+HDR, g.end)
                off += gs
                continue
            ds, fl, fid = struct.unpack_from('<III', raw, off+4)
            r = Node('rec', type=rt, start=off, end=off+HDR+ds, fid=fid, flags=fl,
                     gtype=-1, label=0)
            body = raw[off+HDR:off+HDR+ds]
            if fl & COMPRESSED and len(body) > 4:
                try: body = zlib.decompress(body[4:])
                except Exception: body = b''
            r.body = body
            r.parent = node; node.children.append(r)
            recs[fid] = r
            off += HDR + ds
    walk(root, 0, len(raw))
    return root, recs
