"""Synthetic LevelDB files containing only profile metadata, never personal state."""
import json
import pathlib
import struct
import sys


def varint(n):
    out = bytearray()
    while n >= 128:
        out.append((n & 127) | 128)
        n >>= 7
    out.append(n)
    return bytes(out)


def lp(data):
    return varint(len(data)) + data


def masked_crc(data):
    crc = 0xffffffff
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82f63b78 if crc & 1 else 0)
    crc ^= 0xffffffff
    return struct.pack('<I', (((crc >> 15) | (crc << 17)) + 0xa282ead8) & 0xffffffff)


def snappy(data):
    # Exercise a literal and copy-two tag, including overlapping copies.
    result = bytearray(varint(len(data)))
    p = 0
    while p < len(data):
        best = None
        for off in range(1, min(p, 65535) + 1):
            count = 0
            while count < 64 and p + count < len(data) and data[p + count] == data[p + count - off]:
                count += 1
            if count >= 4:
                best = (count, off)
                break
        if best:
            count, off = best
            result.append(((count - 1) << 2) | 2)
            result += struct.pack('<H', off)
            p += count
        else:
            result.append(0)
            result.append(data[p])
            p += 1
    return bytes(result)


def entries(rows):
    out = bytearray()
    previous = b''
    for key, value in sorted(rows):
        shared = 0
        while shared < min(len(key), len(previous)) and key[shared] == previous[shared]:
            shared += 1
        out += varint(shared) + varint(len(key) - shared) + varint(len(value)) + key[shared:] + value
        previous = key
    return bytes(out) + struct.pack('<II', 0, 1)


def block(data, compressed=False):
    kind = bytes([int(compressed)])
    raw = snappy(data) if compressed else data
    return raw + kind + masked_crc(raw + kind), len(raw)


def table(rows):
    data, n = block(entries(rows), True)
    index, ni = block(entries([(rows[-1][0], varint(0) + varint(n))]))
    footer = varint(0) + varint(0) + varint(len(data)) + varint(ni)
    return data + index + footer.ljust(40, b'\0') + bytes.fromhex('57fb808b247547db')


def record(data, kind=1):
    return masked_crc(bytes([kind]) + data) + struct.pack('<HB', len(data), kind) + data


def key(profile, field):
    return ('persistent###profiles###' + profile + '###' + field).encode()


def rows(profile='active', name='Thornswood', game='skyrimse', sequence=10):
    return [(key(profile, field) + struct.pack('<Q', ((sequence + i) << 8) | 1), json.dumps(value).encode())
            for i, (field, value) in enumerate([('gameId', game), ('name', name)])]


def fixture(root, name, rs=None, wal=None):
    directory = root / name / 'Vortex' / 'state.v2'
    directory.mkdir(parents=True, exist_ok=True)
    rs = rows() if rs is None else rs
    data = table(rs)
    (directory / '000001.ldb').write_bytes(data)
    manifest = varint(2) + varint(3) + varint(3) + varint(4) + varint(4) + varint(100) + varint(7) + varint(0) + varint(1) + varint(len(data)) + lp(rs[0][0]) + lp(rs[-1][0])
    (directory / 'MANIFEST-000002').write_bytes(record(manifest))
    (directory / 'CURRENT').write_text('MANIFEST-000002\n')
    for profile in ['active', 'other', 'obsolete']:
        path = root / name / 'Vortex' / 'skyrimse' / 'profiles' / profile
        path.mkdir(parents=True, exist_ok=True)
        (path / 'plugins.txt').write_text('*Thornswood-Content.esp\n')
    if wal is not None:
        (directory / '000003.log').write_bytes(wal)
    return directory


def batch(field, value=None, deleted=False, sequence=20):
    return struct.pack('<QI', sequence, 1) + bytes([0 if deleted else 1]) + lp(key('active', field)) + (b'' if deleted else lp(json.dumps(value).encode()))


root = pathlib.Path(sys.argv[1])
fixture(root, 'compressed')
fixture(root, 'renamed', wal=record(batch('name', 'Different')))
fixture(root, 'deleted', wal=record(batch('name', deleted=True)))
fixture(root, 'different-game', rows(game='fallout4'))
fixture(root, 'duplicate', rows() + rows('other', sequence=30))
fixture(root, 'escaped', rows(name='Thorns\"wood'))
directory = fixture(root, 'obsolete', rows(name='Different'))
(directory / '000099.ldb').write_bytes(table(rows('obsolete', sequence=100)))
directory = fixture(root, 'corrupt')
data = bytearray((directory / '000001.ldb').read_bytes())
data[0] ^= 1
(directory / '000001.ldb').write_bytes(data)
fixture(root, 'partial', wal=record(batch('name', 'Different'))[:-4])
fixture(root, 'fragmented', wal=record(batch('name', 'Different')[:18], 2) + record(batch('name', 'Different')[18:], 4))
directory = fixture(root, 'unknown-manifest')
(directory / 'MANIFEST-000002').write_bytes(record(varint(123)))
directory = fixture(root, 'missing-manifest-fields')
(directory / 'MANIFEST-000002').write_bytes(record(varint(2) + varint(3)))
directory = fixture(root, 'current-no-newline')
(directory / 'CURRENT').write_text('MANIFEST-000002')
directory = fixture(root, 'duplicate-missing-list', rows() + rows('other', sequence=30))
(root / 'duplicate-missing-list' / 'Vortex' / 'skyrimse' / 'profiles' / 'other' / 'plugins.txt').unlink()
invalid = rows()
invalid[0] = (invalid[0][0][:-8] + struct.pack('<Q', (10 << 8) | 2), invalid[0][1])
fixture(root, 'invalid-kind', invalid)
fixture(root, 'equal-conflict', rows() + rows(name='Different'))
fixture(root, 'equal-identical', rows() + rows())
fixture(root, 'short-header', wal=record(batch('name', 'Different'))[:6])
fixture(root, 'interrupted', wal=record(batch('name', 'Different')[:18], 2) + record(batch('name', 'Different')))


def fragmented_log(batches):
    out = bytearray()
    for data in batches:
        p = 0
        while p < len(data):
            remain = 32768 - len(out) % 32768
            if remain < 7:
                out += b'\0' * remain
                remain = 32768
            n = min(remain - 7, len(data) - p)
            first, last = p == 0, p + n == len(data)
            kind = 1 if first and last else 2 if first else 4 if last else 3
            out += record(data[p:p+n], kind)
            p += n
    return out


large = struct.pack('<QI', 30, 1) + b'\1' + lp(b'persistent###unrelated') + lp(b'x' * 70000)
fixture(root, 'two-large-fragments', wal=fragmented_log([large, large, batch('name', 'Different', sequence=50)]))
malformed = rows()
malformed[1] = (malformed[1][0], b'"Thornswood"{}')
fixture(root, 'trailing-json', malformed)
malformed[1] = (malformed[1][0], b'123')
fixture(root, 'number-json', malformed)
