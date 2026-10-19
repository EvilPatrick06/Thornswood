"""
Build-StartMenu.py

Writes launcher\\app\\FromGameMenu.cs: Thornswood's edit to Skyrim's main menu,
as the bytes that change, so the launcher can make the menu from each
person's own game (#2827) instead of shipping it.

    Data\\Interface\\startmenu.swf

WHY

Thornswood's main menu is Skyrim's own interface\\startmenu.swf with its
Bethesda logo shapes taken out (#2177). Measured 15 Oct: the same 871 SWF tags
in the same order as the game's, only DefineShape tags differ, by a byte or
two each. Bethesda's terms grant no right to hand on the game's own files,
edited or not (#2792, #2827), so since #2827 the file does not ship. Patrick
chose on 19 Oct that the launcher makes it on each machine from that machine's
own Skyrim - Interface.bsa (option 2). What ships is this script's output:
where each changed byte is and what it becomes, the sha256 of the game's file
the edit is made against, and the sha256 of the menu it must come to.

HOW

The game's file and the edited one are both compressed SWFs (CWS): an 8 byte
header, then the rest through zlib. Both are unpacked and read tag by tag; the
tags must be the same kinds in the same order, and each pair that differs is
compared byte by byte (difflib), so an edit is only the bytes that changed.
Then the edit is applied to the game's file and packed again the way the
edited file was packed (zlib level 6, which the launcher's FromGameDeflate.cs
does to the bit), and the result must be the edited file byte for byte, or
nothing is written.

Usage, on a machine with the game (the archive is read, never written):
    python scripts/mods/Build-StartMenu.py           write launcher\\app\\FromGameMenu.cs
    python scripts/mods/Build-StartMenu.py --check   say whether FromGameMenu.cs is
                                                    what this writes
    --data <the game's Data folder>, default C:\\Thornswood\\Game\\Data
    --edited <file>   the edited menu; by default the one that shipped until
                      #2827, read out of git at commit 66c0c6c6 (#1260)
    --recipe <file> and --name <C# name>: where the recipe goes and what it is
                      called (tests\\fixtures\\2827 uses these for its made-up game)
Exit 1 when a check fails or a file cannot be read.
"""

import argparse
import difflib
import hashlib
import os
import runpy
import struct
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
RECIPE = os.path.join(REPO, 'launcher', 'app', 'FromGameMenu.cs')
DATA = 'C:\\Thornswood\\Game\\Data'
ARCHIVE = 'Skyrim - Interface.bsa'
SOURCE = 'interface\\startmenu.swf'
PATH = 'Data\\Interface\\startmenu.swf'
SHIPPED = ('66c0c6c6', 'game/ours/Data/Interface/startmenu.swf')  # the commit that kept it (#1260)


def unpack(swf, what):
    """The whole SWF uncompressed, its 8 byte header included."""
    if swf[:3] != b'CWS':
        raise SystemExit('STOP. %s is not a compressed SWF (it starts %r).' % (what, swf[:3]))
    d = zlib.decompressobj()
    body = d.decompress(swf[8:]) + d.flush()
    if d.unused_data or len(body) + 8 != struct.unpack_from('<I', swf, 4)[0]:
        raise SystemExit('STOP. %s does not unpack to the length its header says.' % what)
    return swf[:8] + body


def pack(plain):
    """zlib level 6, window 15, memory level 8, the default strategy: what the
    edited menu was packed with, and what FromGameDeflate.cs does."""
    c = zlib.compressobj(6, zlib.DEFLATED, 15, 8, zlib.Z_DEFAULT_STRATEGY)
    return b'CWS' + plain[3:8] + c.compress(plain[8:]) + c.flush()


def pieces(plain, what):
    """The header (to the end of the frame count), then each tag whole: (code, start, end)."""
    nbits = plain[8] >> 3
    o = 8 + (5 + 4 * nbits + 7) // 8 + 4
    out = [(-1, 0, o)]
    while o < len(plain):
        cl = struct.unpack_from('<H', plain, o)[0]
        code, n, h = cl >> 6, cl & 0x3F, 2
        if n == 0x3F:
            n, h = struct.unpack_from('<I', plain, o + 2)[0], 6
        if o + h + n > len(plain):
            raise SystemExit('STOP. %s has a tag that runs past its end.' % what)
        out.append((code, o, o + h + n))
        o += h + n
        if code == 0:
            break
    if o != len(plain):
        raise SystemExit('STOP. %s goes on after its end tag.' % what)
    return out


def edits_between(game, edited):
    a, b = pieces(game, 'the game\'s menu'), pieces(edited, 'the edited menu')
    if [c for c, _, _ in a] != [c for c, _, _ in b]:
        raise SystemExit('STOP. The edited menu does not have the game\'s tags in the game\'s order, so '
                         'it is not an edit of this file; is the game on the build Thornswood pins?')
    out = []
    for (code, a0, a1), (_, b0, b1) in zip(a, b):
        x, y = game[a0:a1], edited[b0:b1]
        if x == y:
            continue
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, x, y, autojunk=False).get_opcodes():
            if op != 'equal':
                out.append((a0 + i1, i2 - i1, y[j1:j2].hex(), code))
    return out


def apply(game, edits):
    out, at = bytearray(), 0
    for e_at, remove, insert, _ in edits:
        out += game[at:e_at] + bytes.fromhex(insert)
        at = e_at + remove
    return bytes(out + game[at:])


KINDS = {-1: 'the header', 2: 'DefineShape', 22: 'DefineShape2', 32: 'DefineShape3', 83: 'DefineShape4'}


def recipe(name, src, edited_file, edits):
    i3, i4 = ' ' * 12, ' ' * 16
    L = ['// Written by scripts\\mods\\Build-StartMenu.py from the game\'s menu and Thornswood\'s,',
         '// on a machine with the game. Run it again rather than editing this; an edit here',
         '// fails the launcher\'s byte for byte check (#2827).',
         'namespace Thornswood',
         '{',
         '    public sealed partial class MenuRecipe',
         '    {',
         '        public static readonly MenuRecipe %s = new MenuRecipe' % name,
         '        {',
         i3 + 'Archive = "%s",' % ARCHIVE,
         i3 + 'Source = "%s",' % SOURCE.replace('\\', '\\\\'),
         i3 + 'SourceSize = %d,' % len(src),
         i3 + 'SourceSha256 = "%s",' % hashlib.sha256(src).hexdigest(),
         i3 + 'Path = "%s",' % PATH.replace('\\', '\\\\'),
         i3 + 'Size = %d,' % len(edited_file),
         i3 + 'Sha256 = "%s",' % hashlib.sha256(edited_file).hexdigest(),
         i3 + 'Edits = new[]',
         i3 + '{']
    L += [i4 + 'new MenuEdit(%d, %d, "%s"), // in %s' % (at, remove, insert, KINDS.get(code, 'tag %d' % code))
          for at, remove, insert, code in edits]
    L += [i3 + '},',
          '        };',
          '    }',
          '}',
          '']
    return '\r\n'.join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=DATA)
    ap.add_argument('--edited')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--recipe', default=RECIPE)
    ap.add_argument('--name', default='Shipped')
    args = ap.parse_args()

    path = os.path.join(args.data, ARCHIVE)
    if not os.path.isfile(path):
        print('STOP. %s is not in %s. Give --data the game\'s Data folder.' % (ARCHIVE, args.data))
        return 1
    Archive = runpy.run_path(os.path.join(HERE, 'Build-NoticeBoard.py'), run_name='board')['Archive']
    archive = Archive(path)
    if SOURCE not in archive.files:
        print('STOP. %s has no %s.' % (ARCHIVE, SOURCE))
        return 1
    src = archive.read(SOURCE)
    if args.edited:
        edited_file = open(args.edited, 'rb').read()
    else:
        edited_file = subprocess.run(['git', '-C', REPO, 'show', '%s:%s' % SHIPPED],
                                     capture_output=True, check=True).stdout
    game, edited = unpack(src, 'the game\'s menu'), unpack(edited_file, 'the edited menu')
    edits = edits_between(game, edited)
    if apply(game, edits) != edited:
        print('STOP. The edits do not make the edited menu from the game\'s.')
        return 1
    if pack(edited) != edited_file:
        print('STOP. Packing the edited menu again does not give its bytes: either this Python\'s zlib is not '
              'the classic one (zlib.ZLIB_RUNTIME_VERSION says %s), or the edited menu was not packed at level 6. '
              'The launcher could not make it byte for byte, so nothing is written.' % zlib.ZLIB_RUNTIME_VERSION)
        return 1
    print('the game\'s %s: %s bytes, sha256 %s' % (SOURCE, format(len(src), ','), hashlib.sha256(src).hexdigest()))
    print('the edited menu: %s bytes, sha256 %s' % (format(len(edited_file), ','),
                                                    hashlib.sha256(edited_file).hexdigest()))
    tags = pieces(game, 'the game\'s menu')[1:]
    print('%d edits, %d bytes taken out and %d put in, in %d of %d tags' % (
        len(edits), sum(e[1] for e in edits), sum(len(e[2]) // 2 for e in edits),
        sum(1 for _, a0, a1 in tags if any(a0 <= e[0] < a1 for e in edits)), len(tags)))
    text = recipe(args.name, src, edited_file, edits)
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
