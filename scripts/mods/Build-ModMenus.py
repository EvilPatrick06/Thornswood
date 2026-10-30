"""
Build-ModMenus.py

Writes launcher\\app\\FromGameModMenus.cs: Thornswood's edits to the menus of
three of the collection's mods, as the bytes that change, so the launcher can
make the edited menus on each machine from that machine's own copy of those
mods (#3113), the way it makes the main menu from the game's (#2827).

    Data\\Interface\\skyui\\config.txt         SkyUI's item lists
    Data\\Interface\\skyui\\itemcard.swf       SkyUI's item card
    Data\\Interface\\hudmenu.swf               SkyHUD's HUD
    Data\\Interface\\AHZHudInfo.swf            moreHUD's HUD widget, and its
    Data\\Interface\\exported\\AHZHudInfo.swf  copy under exported

WHY

An item on Thornswood has no gold price: "What it sells for is the price a
person posts" (docs\\systems\\professions.md, docs\\GAME-SYSTEMS.md). Patrick, 21 Oct
2026, on the report page: "this is an RP server and the gold prices listed dont
even matter also one of the things was supposed to remove the listed prices
entirly". Measured 21 Oct from the collection's own archives (revision 4: SkyUI
file 749043, SkyHUD 61422, moreHUD 803483), every place an item's built-in gold
value is drawn, and what draws it:

  1. The Value and V/W columns of every item list: inventory, container,
     barter, gift, and the crafting menus (Crafting Categories' smithing menu
     reads the same file). SkyUI's interface\\skyui\\config.txt names them in
     each view's columns line.
  2. VALUE and its number on the item card under every one of those lists.
     SkyUI's interface\\skyui\\itemcard.swf places a "$VALUE" label and the
     ItemValueText field on each kind of card (weapons, apparel, potions,
     ingredients, books, misc and the rest).
  3. VALUE and its number under the name when somebody looks at an item lying
     in the world. The engine hands the HUD the item's value (aCost) and
     SkyHUD's interface\\hudmenu.swf, which wins over SkyUI's because SkyHUD.esp
     loads later, writes it into RolloverInfoText in SetCrosshairTarget.
  4. moreHUD's V/W, appended to that same line. Its plugin reads the last two
     numbers of the line as weight and value, so with the value gone it would
     divide the damage or armour by the weight. Its widget,
     interface\\AHZHudInfo.swf, turns it on from the AHZShowVW setting in
     updateSettings.

QuickLoot's Val and V/W columns are the fifth; they are a setting, not a menu
edit (game\\ours\\Data\\SKSE\\Plugins\\QuickLootIE.json).

WHAT EACH EDIT IS

  config.txt      valueColumn, valueWeightColumn, alchValueColumn and
                  alchValueWeightColumn come out of every views.*.columns line.
                  The columns' own definitions stay; no view names them.
  itemcard.swf    every PlaceObject of a "$VALUE" label and of ItemValueText is
                  taken out, in every frame. ItemCard's own script already asks
                  whether ItemValueText is there before it writes to it.
  hudmenu.swf     the test before the value is written, "if (aCost !=
                  undefined)", is made to fail always: the push of aCost
                  becomes a push of true, and the second Not a ToNumber, so the
                  If always jumps past the block. Same length, nothing moves.
  AHZHudInfo.swf  "showValueToWeight = showValueToWeightValue >= 1" reads false
                  in place of the setting, so it is always false. Same length.

Each edit is checked for what it must find (how many places, which bytes) and
stops when the mod's file is not the one it was written for. The recipe pins
each source by sha256, so a new release of one of these mods makes nothing
until this is run again against it, and the launcher says which file differs.

Then each file is made the way the launcher makes it (the edits applied, a
movie packed again with zlib level 6, which FromGameDeflate.cs does to the
bit), and its sha256 goes in the recipe.

Usage, with the collection's archives in a Data folder (read, never written):
    python scripts/mods/Build-ModMenus.py --data <Data>           write the recipe
    python scripts/mods/Build-ModMenus.py --data <Data> --check   say whether it is what this writes
    --recipe <file>   where the recipe goes (default launcher\\app\\FromGameModMenus.cs)
Exit 1 when a check fails or a file cannot be read. Plain Python: none of the
three archives is compressed; a compressed one needs the lz4 module.
"""

import argparse
import hashlib
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
RECIPE = os.path.join(REPO, 'launcher', 'app', 'FromGameModMenus.cs')
DATA = 'C:\\Thornswood\\Game\\Data'


# ------------------------------------------------------------------ archives

def read_archive(path, want):
    """The file at want (folder\\leaf, any case) in a version 105 archive, unpacked."""
    with open(path, 'rb') as f:
        h = f.read(36)
        if h[:4] != b'BSA\x00' or struct.unpack_from('<I', h, 4)[0] != 105:
            raise SystemExit('STOP. %s is not a Skyrim Special Edition archive.' % path)
        foff, flags, nfold, nfile, lfold, lfile = struct.unpack_from('<IIIIII', h, 8)
        if flags & 3 != 3:
            raise SystemExit('STOP. %s does not carry its folder and file names.' % path)
        f.seek(foff)
        counts = [struct.unpack('<QIIQ', f.read(24))[1] for _ in range(nfold)]
        recs = []
        for c in counts:
            n = f.read(1)[0]
            folder = f.read(n)[:-1].decode('latin-1')
            for _ in range(c):
                _, size, off = struct.unpack('<QII', f.read(16))
                recs.append((folder, size, off))
        names = f.read(lfile).split(b'\x00')
        for (folder, size, off), leaf in zip(recs, names):
            if (folder + '\\' + leaf.decode('latin-1')).lower() != want.lower():
                continue
            packed = bool(flags & 4) ^ bool(size & 0x40000000)
            size &= 0x3FFFFFFF
            f.seek(off)
            if flags & 0x100:
                n = f.read(1)[0]
                f.read(n)
                size -= n + 1
            raw = f.read(size)
            if not packed:
                return raw
            try:
                import lz4.frame
            except ImportError:
                raise SystemExit('STOP. %s in %s is LZ4 packed and this Python has no lz4 module.' % (want, path))
            return lz4.frame.decompress(raw[4:])
    raise SystemExit('STOP. %s has no %s.' % (path, want))


# ---------------------------------------------------------------------- movies

def unpack(swf, what):
    """The whole movie uncompressed, its 8 byte header included."""
    if swf[:3] != b'CWS':
        raise SystemExit('STOP. %s is not a compressed SWF (it starts %r).' % (what, swf[:3]))
    d = zlib.decompressobj()
    body = d.decompress(swf[8:]) + d.flush()
    if d.unused_data or len(body) + 8 != struct.unpack_from('<I', swf, 4)[0]:
        raise SystemExit('STOP. %s does not unpack to the length its header says.' % what)
    return swf[:8] + body


def pack(plain):
    """zlib level 6, window 15, memory level 8, the default strategy: what
    FromGameDeflate.cs does, so the launcher makes these bytes."""
    c = zlib.compressobj(6, zlib.DEFLATED, 15, 8, zlib.Z_DEFAULT_STRATEGY)
    return b'CWS' + plain[3:8] + c.compress(plain[8:]) + c.flush()


def tags(b, o, end, what):
    """Each tag from o to end: (code, start, body start, end)."""
    out = []
    while o < end:
        cl = struct.unpack_from('<H', b, o)[0]
        code, n, h = cl >> 6, cl & 0x3F, 2
        if n == 0x3F:
            n, h = struct.unpack_from('<I', b, o + 2)[0], 6
        if o + h + n > end:
            raise SystemExit('STOP. %s has a tag that runs past its end.' % what)
        out.append((code, o, o + h, o + h + n))
        o += h + n
        if code == 0:
            break
    if o != end:
        raise SystemExit('STOP. %s goes on after its end tag.' % what)
    return out


def header_end(plain):
    nbits = plain[8] >> 3
    return 8 + (5 + 4 * nbits + 7) // 8 + 4


def place_character(b, s, body):
    """The character a PlaceObject2 (26) or PlaceObject3 (70) places, or None."""
    code = struct.unpack_from('<H', b, s)[0] >> 6
    f1 = b[body]
    o = body + (2 if code == 70 else 1) + 2
    if code == 70:
        f2 = b[body + 1]
        if f2 & 0x08 or (f2 & 0x10 and f1 & 0x02):
            o = b.index(0, o) + 1
    if not f1 & 0x02:
        return None
    return struct.unpack_from('<H', b, o)[0]


def edit_itemcard(plain):
    """Takes out every placement of a "$VALUE" label and of ItemValueText.
    Each sprite that loses one gets its length again, and so does the movie."""
    top = tags(plain, header_end(plain), len(plain), 'the item card')
    labels = set()
    for code, s, b0, e in top:
        if code == 37 and b'>$VALUE</font>' in plain[b0:e]:
            labels.add(struct.unpack_from('<H', plain, b0)[0])
    if not labels:
        raise SystemExit('STOP. The item card has no "$VALUE" label, so it is not the card this edit was written for.')
    edits, cut = [], 0
    gone = {'label': 0, 'field': 0}
    for code, s, b0, e in top:
        if code != 39:
            continue
        drop = []
        for c, ss, sb, se in tags(plain, b0 + 4, e, 'a sprite of the item card'):
            if c not in (26, 70):
                continue
            if place_character(plain, ss, sb) in labels:
                gone['label'] += 1
                drop.append((ss, se))
            elif b'ItemValueText\x00' in plain[sb:se]:
                gone['field'] += 1
                drop.append((ss, se))
        if not drop:
            continue
        n = e - b0 - sum(se - ss for ss, se in drop)
        edits.append((s, b0 - s, struct.pack('<HI', (39 << 6) | 0x3F, n).hex()))
        edits += [(ss, se - ss, '') for ss, se in drop]
        cut += sum(se - ss for ss, se in drop) - (6 - (b0 - s))
    if gone['field'] < 10 or gone['label'] < 10:
        raise SystemExit('STOP. The item card had %d value labels and %d value fields to take out; the card this '
                         'edit was written for has at least ten of each.' % (gone['label'], gone['field']))
    edits.insert(0, (4, 4, struct.pack('<I', len(plain) - cut).hex()))
    return edits, '%d "$VALUE" labels and %d ItemValueText fields taken out' % (gone['label'], gone['field'])


def edit_once(plain, before, after, what):
    """The one place before is, changed to after, as the bytes that differ."""
    if len(before) != len(after):
        raise SystemExit('STOP. %s: an edit must keep the length.' % what)
    n = plain.count(before)
    if n != 1:
        raise SystemExit('STOP. %s: the bytes this edit changes are there %d times, not once, so it is not the file '
                         'it was written for.' % (what, n))
    at = plain.index(before)
    return [(at + i, 1, '%02x' % after[i]) for i in range(len(before)) if before[i] != after[i]]


# SetCrosshairTarget, at "if (aCost != undefined)": Push register14 (aCost),
# undefined; Equals2; Not; Not; If past the block that writes VALUE. Then the
# block's first push, register1 and "ValueTranslated", is matched too, so the
# bytes are the ones in front of the value and nowhere else. After: Push true,
# undefined; Equals2 (false); Not (true); ToNumber (1); If, which always jumps.
HUD_BEFORE = bytes.fromhex('960300040e03' '491212' '9d02003f00' '9605000401096201')
HUD_AFTER = bytes.fromhex('960300050103' '49124a' '9d02003f00' '9605000401096201')

# updateSettings: Push register1, "showValueToWeight", register11, 1; Less2;
# Not; SetMember. register11 (the setting) becomes false, and false < 1, so
# the Not stores false whatever the setting says.
VW_BEFORE = bytes.fromhex('960b000401083a040b0701000000' '48124f')
VW_AFTER = bytes.fromhex('960b000401083a05000701000000' '48124f')


def edit_hud(plain):
    return edit_once(plain, HUD_BEFORE, HUD_AFTER, 'SkyHUD\'s HUD'), 'the value test in SetCrosshairTarget never passes'


def edit_morehud(plain):
    return edit_once(plain, VW_BEFORE, VW_AFTER, 'moreHUD\'s widget'), 'showValueToWeight is always false'


# ---------------------------------------------------------------- the config

VALUE_COLUMNS = ('valueColumn', 'valueWeightColumn', 'alchValueColumn', 'alchValueWeightColumn')


def edit_config(text):
    """Each views line that names a value column, without it."""
    edits, at = [], 0
    for line in text.split(b'\n'):
        s = line.decode('latin-1')
        if s.startswith('views.') and '.columns' in s.split('=')[0] and '<' in s:
            head, rest = s.split('<', 1)
            inner, tail = rest.split('>', 1)
            cols = [c.strip() for c in inner.split(',')]
            keep = [c for c in cols if c not in VALUE_COLUMNS]
            if keep != cols:
                new = (head + '<' + ', '.join(keep) + '>' + tail).encode('latin-1')
                p = 0
                while line[p] == new[p]:
                    p += 1
                q = 0
                while line[-1 - q] == new[-1 - q] and len(new) - q > p:
                    q += 1
                edits.append((at + p, len(line) - p - q, new[p:len(new) - q].hex()))
        at += len(line) + 1
    if len(edits) < 10:
        raise SystemExit('STOP. SkyUI\'s config had %d views with a value column; the one this edit was written for '
                         'has twelve.' % len(edits))
    return edits, 'the value columns taken out of %d views' % len(edits)


# --------------------------------------------------------------------- recipes

# (C# name, mod, archive, path in it, path in the game folder, edit, kind)
MENUS = [
    ('SkyUIConfig', 'SkyUI', 'SkyUI_SE.bsa', 'interface\\skyui\\config.txt', 'Data\\Interface\\skyui\\config.txt', edit_config, 'text'),
    ('SkyUIItemCard', 'SkyUI', 'SkyUI_SE.bsa', 'interface\\skyui\\itemcard.swf', 'Data\\Interface\\skyui\\itemcard.swf', edit_itemcard, 'movie'),
    ('SkyHUDMenu', 'SkyHUD', 'SkyHUD.bsa', 'interface\\hudmenu.swf', 'Data\\Interface\\hudmenu.swf', edit_hud, 'movie'),
    ('MoreHUDInfo', 'moreHUD', 'AHZmoreHUD.bsa', 'interface\\ahzhudinfo.swf', 'Data\\Interface\\AHZHudInfo.swf', edit_morehud, 'movie'),
    ('MoreHUDInfoExported', 'moreHUD', 'AHZmoreHUD.bsa', 'interface\\exported\\ahzhudinfo.swf', 'Data\\Interface\\exported\\AHZHudInfo.swf', edit_morehud, 'movie'),
]


def apply(a, edits):
    out, at = bytearray(), 0
    for e_at, remove, insert in edits:
        out += a[at:e_at] + bytes.fromhex(insert)
        at = e_at + remove
    return bytes(out + a[at:])


def make(data, menu):
    name, mod, archive, source, path, edit, kind = menu
    where = os.path.join(data, archive)
    if not os.path.isfile(where):
        raise SystemExit('STOP. %s is not in %s. Give --data the Data folder the collection is in.' % (archive, data))
    src = read_archive(where, source)
    plain = unpack(src, source) if kind == 'movie' else src
    edits, said = edit(plain)
    edits.sort()
    edited = apply(plain, edits)
    if kind == 'movie':
        tags(edited, header_end(edited), len(edited), 'the edited ' + path)
        if struct.unpack_from('<I', edited, 4)[0] != len(edited):
            raise SystemExit('STOP. %s: the edited movie\'s header does not say its length.' % path)
    made = pack(edited) if kind == 'movie' else edited
    return {'name': name, 'mod': mod, 'archive': archive, 'source': source, 'path': path, 'src': src,
            'made': made, 'edits': edits, 'said': said}


def cs(s):
    return s.replace('\\', '\\\\')


def recipe(made):
    i2, i3, i4 = ' ' * 8, ' ' * 12, ' ' * 16
    L = ['// Written by scripts\\mods\\Build-ModMenus.py from the collection\'s SkyUI, SkyHUD and',
         '// moreHUD archives. Run it again rather than editing this; an edit here fails the',
         '// launcher\'s byte for byte check (#3113).',
         'namespace Thornswood',
         '{',
         '    public sealed partial class MenuRecipe',
         '    {']
    for m in made:
        L += [i2 + 'public static readonly MenuRecipe %s = new MenuRecipe' % m['name'],
              i2 + '{',
              i3 + 'Mod = "%s",' % m['mod'],
              i3 + 'Archive = "%s",' % m['archive'],
              i3 + 'Source = "%s",' % cs(m['source']),
              i3 + 'SourceSize = %d,' % len(m['src']),
              i3 + 'SourceSha256 = "%s",' % hashlib.sha256(m['src']).hexdigest(),
              i3 + 'Path = "%s",' % cs(m['path']),
              i3 + 'Size = %d,' % len(m['made']),
              i3 + 'Sha256 = "%s",' % hashlib.sha256(m['made']).hexdigest(),
              i3 + 'Edits = new[]',
              i3 + '{']
        L += [i4 + 'new MenuEdit(%d, %d, "%s"),' % e for e in m['edits']]
        L += [i3 + '},',
              i2 + '};',
              '']
    L += [i2 + '/// <summary>Every mod menu FromGame makes, in this order.</summary>',
          i2 + 'public static readonly MenuRecipe[] Mods = { %s };' % ', '.join(m['name'] for m in made),
          '    }', '}', '']
    return '\n'.join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=DATA)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--recipe', default=RECIPE)
    args = ap.parse_args()
    made = [make(args.data, m) for m in MENUS]
    for m in made:
        print('%-42s %s: %s bytes from %s bytes (sha256 %s), %d edits' % (
            m['path'], m['said'], format(len(m['made']), ','), format(len(m['src']), ','),
            hashlib.sha256(m['made']).hexdigest()[:16], len(m['edits'])))
    text = recipe(made)
    if args.check:
        have = open(args.recipe, 'rb').read().decode('utf-8') if os.path.isfile(args.recipe) else None
        same = have is not None and have.replace('\r\n', '\n') == text.replace('\r\n', '\n')
        print('  ok    %s is what this writes' % args.recipe if same else
              '  DIFFERS  %s is not what this writes' % args.recipe)
        return 0 if same else 1
    open(args.recipe, 'wb').write(text.encode('utf-8'))
    print('wrote ' + args.recipe)
    return 0


if __name__ == '__main__':
    sys.exit(main())
