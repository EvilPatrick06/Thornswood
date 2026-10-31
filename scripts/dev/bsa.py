"""
bsa.py

Reads files out of a Skyrim BSA archive, and reads a .STRINGS table out of the
bytes that come back.

WHY IT EXISTS

A cell's display name is not in the plugin. A localised plugin stores FULL as a
four byte STRING ID, and the text it points at lives in a .STRINGS file inside
Skyrim - Interface.bsa. Measured 21 September: 583 of the 590 interior cells in
Skyrim.esm carry FULL, and every one of them is four bytes.

Nothing can be called Breezehome without this. The deed the property system
hands over says which building it is, and a deed reading "Deed to
WhiterunBreezehome" is the editor id leaking out to a person.

Build-RecipeTable.ps1 already does this in PowerShell, for item names. This is
the Python side of the same job, kept in its own file because a door table, an
item table and whatever comes next all want it and none of them should own it.

WHAT A BSA IS. A header, a list of folders, a list of files per folder, then all
the names, then the data. A file may be compressed, which is a four byte
uncompressed length and then zlib, and whether it is compressed is an archive
wide flag that an individual file may invert. Names may be embedded at the front
of the data as well, which has to be skipped when they are.

In a version 105 archive, which is every archive Skyrim Special Edition makes,
the compressed data is an LZ4 frame and not zlib. Measured 24 September: every
compressed file in Gourmet.bsa, RaceMenu.bsa, UIExtensions.bsa and Apocalypse -
Magic of Skyrim.bsa starts 04 22 4D 18 after its length, which is the LZ4 frame
magic, and zlib refused every one of them. Ten of the twenty five archives in
the game folder that carry scripts are compressed, and none of them could be
read here before this. Python has no LZ4 without a package, so the decoder is
below; it is short, because LZ4 is only literals and copies.

Read only. It opens files and never writes one.
"""

import mmap
import os
import struct
import zlib

HEADER = 36
FLAG_COMPRESSED = 0x004
FLAG_EMBEDDED_NAMES = 0x100
SIZE_MASK = 0x3FFFFFFF
INVERT_COMPRESSION = 0x40000000
LZ4_MAGIC = 0x184D2204


def read(path, wanted_folder=None):
    """Every file in the archive, as {'folder/name': bytes}.

    wanted_folder limits it to one folder, compared without case, because
    pulling a 400MB archive into memory to read one string table would be silly.

    The archive is mapped rather than read, so only the pages actually looked at
    come off the disk. It used to be read whole: measured 24 September, looking
    for the scripts folder in all 63 archives in the game folder took 80 seconds,
    nearly all of it reading textures, sounds and voices nobody asked for.
    Mapped, the same took 1.8.
    """
    with open(path, 'rb') as fh:
        buf = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
    try:
        return _read(buf, path, wanted_folder)
    finally:
        buf.close()


def names(path):
    """Every file path in the archive, as 'folder/name', and none of the data.

    For a question about which files an archive holds (List-ToolRecords.py
    asks which models Skyrim's mesh archives carry, #3162), where inflating
    every mesh of a 1 GB archive in pure Python to read its name would take
    minutes and answer nothing more.
    """
    with open(path, 'rb') as fh:
        buf = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
    try:
        return _read(buf, path, None, names_only=True)
    finally:
        buf.close()


def _read(buf, path, wanted_folder, names_only=False):
    if len(buf) < HEADER or buf[:4] != b'BSA\x00':
        raise ValueError('%s is not a BSA' % path)
    (version, offset, flags, folder_count, file_count,
     folder_names_len, file_names_len) = struct.unpack_from('<7I', buf, 4)

    # A v105 folder record carries two extra padding words around a 64 bit
    # offset. Anything older is the 16 byte shape.
    rec = 24 if version >= 105 else 16
    folders, p = [], offset
    for _ in range(folder_count):
        if version >= 105:
            _hash, count, _pad, off, _pad2 = struct.unpack_from('<QIIII', buf, p)
        else:
            _hash, count, off = struct.unpack_from('<QII', buf, p)
        folders.append((count, off))
        p += rec

    # The folder name and its file records sit together, at the offset the
    # folder record gave, minus the total file name length the header counted.
    out, order = {}, []
    for count, off in folders:
        q = off - file_names_len
        name_len = buf[q]
        name = buf[q + 1:q + name_len].decode('ascii', 'replace').rstrip('\x00')
        q += 1 + name_len
        take = wanted_folder is None or name.lower() == wanted_folder.lower()
        for _ in range(count):
            fhash, size, foff = struct.unpack_from('<QII', buf, q)
            q += 16
            order.append((name, size, foff, take))

    # Then every file name in the archive, in the same order, one after another.
    # The block begins where the folder blocks end: the folder records, then for
    # each folder a length byte and its name, then its file records. The header's
    # totalFolderNameLength counts the names and their nulls but not the length
    # bytes, which is what the + folder_count is.
    p = offset + folder_count * rec + folder_names_len + folder_count + file_count * 16
    names = []
    for _ in range(file_count):
        e = buf.find(b'\x00', p)
        if e < 0:
            raise ValueError('%s ends inside its file names' % path)
        names.append(buf[p:e].decode('ascii', 'replace'))
        p = e + 1

    if names_only:
        return ['%s/%s' % (folder.replace('\\', '/').lower(), fname.lower())
                for (folder, _size, _foff, _take), fname in zip(order, names)]

    for (folder, size, foff, take), fname in zip(order, names):
        if not take:
            continue
        compressed = bool(flags & FLAG_COMPRESSED)
        if size & INVERT_COMPRESSION:
            compressed = not compressed
        n = size & SIZE_MASK
        q = foff
        if flags & FLAG_EMBEDDED_NAMES:
            embedded = buf[q]
            q += 1 + embedded
            n -= 1 + embedded
        if compressed:
            original = struct.unpack_from('<I', buf, q)[0]
            if version >= 105:
                data = lz4_frame(buf[q + 4:q + n])
            else:
                data = zlib.decompress(buf[q + 4:q + n])
            if len(data) != original:
                raise ValueError('%s/%s inflated to the wrong size' % (folder, fname))
        else:
            data = buf[q:q + n]
        out['%s/%s' % (folder.replace('\\', '/').lower(), fname.lower())] = data
    return out


def lz4_frame(data):
    """One LZ4 frame, inflated.

    The frame is the magic, a flag byte, a block size byte, then an eight byte
    content size and a four byte dictionary id if the flags say so, then a
    header checksum. Then blocks, each a four byte length whose top bit means
    stored rather than compressed, each followed by a checksum if the flags say
    so, until a length of zero. Blocks may copy from the blocks before them,
    which is why they all inflate into one buffer.
    """
    if len(data) < 7 or struct.unpack_from('<I', data, 0)[0] != LZ4_MAGIC:
        raise ValueError('not an LZ4 frame')
    flags = data[4]
    p = 6
    if flags & 0x08:
        p += 8
    if flags & 0x01:
        p += 4
    p += 1
    out = bytearray()
    while True:
        size = struct.unpack_from('<I', data, p)[0]
        p += 4
        if size == 0:
            break
        n = size & 0x7FFFFFFF
        if p + n > len(data):
            raise ValueError('LZ4 block runs past the end of the frame')
        if size & 0x80000000:
            out += data[p:p + n]
        else:
            _lz4_block(data[p:p + n], out)
        p += n
        if flags & 0x10:
            p += 4
    return bytes(out)


def _lz4_block(src, out):
    """One LZ4 block, appended to out. A block is sequences: a token whose high
    four bits are a literal length and low four a copy length, either one, when
    it is 15, extended by adding the bytes after it until one is less than 255;
    the literals; then a two byte distance back into what is already written.
    The last sequence has literals and no copy. A copy may overlap its own
    output, which repeats the last distance bytes."""
    i, n = 0, len(src)
    while i < n:
        token = src[i]
        i += 1
        run = token >> 4
        if run == 15:
            while True:
                b = src[i]
                i += 1
                run += b
                if b != 255:
                    break
        out += src[i:i + run]
        i += run
        if i >= n:
            break
        back = src[i] | (src[i + 1] << 8)
        i += 2
        length = token & 15
        if length == 15:
            while True:
                b = src[i]
                i += 1
                length += b
                if b != 255:
                    break
        length += 4
        start = len(out) - back
        if back == 0 or start < 0:
            raise ValueError('LZ4 copy reaches before the start of the data')
        if back >= length:
            out += out[start:start + length]
        else:
            out += (out[start:] * (length // back + 1))[:length]


def strings(data, lengthed=False):
    """A .STRINGS table as {string id: text}.

    A .STRINGS file is a count, a data size, then one (id, offset) pair per
    entry, then the text. In .STRINGS the text is null terminated; in
    .DLSTRINGS and .ILSTRINGS every entry is prefixed with its own length,
    which is what lengthed is for.
    """
    count, _size = struct.unpack_from('<II', data, 0)
    base = 8 + count * 8
    out = {}
    for i in range(count):
        sid, off = struct.unpack_from('<II', data, 8 + i * 8)
        p = base + off
        if lengthed:
            n = struct.unpack_from('<I', data, p)[0]
            text = data[p + 4:p + 4 + n]
        else:
            e = data.index(b'\x00', p)
            text = data[p:e]
        out[sid] = text.rstrip(bytes([0])).decode('utf-8', 'replace')
    return out


def load_strings(data_dir, plugin, language='English'):
    """The .STRINGS table for one plugin, out of whichever BSA carries it.

    Loose files in Data\\Strings win over the archives, because that is the
    order the game reads them in. Returns {} when the plugin has no table,
    which is every plugin that is not localised.
    """
    stem = os.path.splitext(plugin)[0]
    name = '%s_%s.strings' % (stem.lower(), language.lower())
    loose = os.path.join(data_dir, 'Strings', name)
    if os.path.isfile(loose):
        return strings(open(loose, 'rb').read())
    for archive in sorted(os.listdir(data_dir)):
        if not archive.lower().endswith('.bsa'):
            continue
        try:
            files = read(os.path.join(data_dir, archive), 'strings')
        except (ValueError, struct.error, zlib.error, IndexError):
            continue
        hit = files.get('strings/' + name)
        if hit:
            return strings(hit)
    return {}
