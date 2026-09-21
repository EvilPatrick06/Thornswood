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

Read only. It opens files and never writes one.
"""

import os
import struct
import zlib

HEADER = 36
FLAG_COMPRESSED = 0x004
FLAG_EMBEDDED_NAMES = 0x100
SIZE_MASK = 0x3FFFFFFF
INVERT_COMPRESSION = 0x40000000


def read(path, wanted_folder=None):
    """Every file in the archive, as {'folder/name': bytes}.

    wanted_folder limits it to one folder, compared without case, because
    pulling a 400MB archive into memory to read one string table would be silly.
    """
    buf = open(path, 'rb').read()
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
        e = buf.index(b'\x00', p)
        names.append(buf[p:e].decode('ascii', 'replace'))
        p = e + 1

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
            data = zlib.decompress(buf[q + 4:q + n])
            if len(data) != original:
                raise ValueError('%s/%s inflated to the wrong size' % (folder, fname))
        else:
            data = buf[q:q + n]
        out['%s/%s' % (folder.replace('\\', '/').lower(), fname.lower())] = data
    return out


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
