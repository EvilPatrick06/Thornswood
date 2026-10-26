"""
Build-SpriteFont.py

Writes game\\ours\\Data\\Platform\\Fonts\\Barlow-SemiBold.spritefont: an
on-screen font for Skyrim Platform drawn from Barlow SemiBold, which is under
the SIL Open Font License (#1317).

WHY

Skyrim Platform draws its on-screen texts (sp.createText) with DirectXTK's
SpriteFont, and loads every .spritefont in Data\\Platform\\Fonts by its name
(DX11RenderHandler.cpp). The overhead voice mark (thornswood-front.js,
MARK_FONT) drew its dot in DIN-Pro-bold.spritefont, which came from upstream
SkyMP's client-deps: a picture of FSI FontShop's DIN Pro Bold, a commercial
face nobody gave Thornswood the right to hand on. This is the same kind of
file made from Barlow SemiBold, the OFL face the fork's interface already
draws its text in in place of DIN Pro (fork #40), so DIN-Pro-bold can go.

HOW

Each character below is drawn with FreeType (through Pillow) at 30 pixels,
the size whose line height, 36, is DIN-Pro-bold's 36.7, so the mark keeps its
size. Each glyph's ink is cut out and packed into one texture, left to right
in rows, one pixel apart. The file is DirectXTK's binary SpriteFont as
SpriteFont.cpp reads it:

    "DXTKfont"
    uint32 glyph count, then per glyph, sorted by character:
        uint32 character; int32 left, top, right, bottom (its texture rect);
        float XOffset, YOffset, XAdvance
    float line spacing; uint32 default character ('?')
    uint32 width, height, DXGI format, row pitch, rows; the texels

DirectXTK draws a glyph at x + XOffset and y + YOffset, then moves x on by
XOffset + its width + XAdvance, so XOffset is the ink's left edge from the
pen, YOffset the ink's top from the top of the line, and XAdvance the rest of
the font's advance. The texels are R8G8B8A8_UNORM (28), premultiplied white
(each one a, a, a, a), the way Tavern.spritefont, Skyrim Platform's own
default, is stored. Rendering is FreeType's, so another FreeType can write
other bytes; --check says which one wrote the file in the repository.

The font is read from the fork at the engine pin,
engine\\skymp\\skymp5-front\\src\\fonts\\Barlow-SemiBold.ttf, and must be the
file THIRD-PARTY.md and records\\asset-provenance.json name (sha256 86577cb3).
Its licence goes out beside the sprite font as Barlow-SemiBold-OFL.txt, as the
OFL asks of a copy that cannot carry it in its own metadata.

Usage:
    python scripts/mods/Build-SpriteFont.py           write the sprite font
    python scripts/mods/Build-SpriteFont.py --check   say whether the file in
                                                     the repository is what
                                                     this writes
    --font <ttf>   Barlow-SemiBold.ttf from somewhere else (it is held to the
                   sha256 all the same)
    --out <file>   where to write, instead of game\\ours
Exit 1 when a check fails or a file cannot be read.

Needs Pillow built with FreeType. Written with Pillow 12.3.0 and FreeType
2.14.3.
"""

import argparse
import hashlib
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFont, features

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
FONT = os.path.join(REPO, 'engine', 'skymp', 'skymp5-front', 'src', 'fonts', 'Barlow-SemiBold.ttf')
FONT_SHA256 = '86577cb32f8abe3673db53ca0f4221e6856751a4f6730c867e00f720f8bb1fc5'
OUT = os.path.join(REPO, 'game', 'ours', 'Data', 'Platform', 'Fonts', 'Barlow-SemiBold.spritefont')
PIXELS = 30
TEXTURE_WIDTH = 512
DEFAULT_CHARACTER = ord('?')
DXGI_FORMAT_R8G8B8A8_UNORM = 28

# Printable ASCII, Latin-1 and the punctuation people type: dashes, curly
# quotes, the bullet (the voice mark) and the ellipsis.
CHARACTERS = (list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) +
              [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026])


def cmap_characters(data):
    """The characters the font's cmap maps to a glyph (formats 4 and 12)."""
    num_tables, = struct.unpack_from('>H', data, 4)
    tables = {}
    for i in range(num_tables):
        tag, _, offset, _ = struct.unpack_from('>4sIII', data, 12 + 16 * i)
        tables[tag] = offset
    if b'cmap' not in tables:
        raise SystemExit('the font has no cmap table')
    base = tables[b'cmap']
    _, count = struct.unpack_from('>HH', data, base)
    have = set()
    for i in range(count):
        platform, encoding, offset = struct.unpack_from('>HHI', data, base + 4 + 8 * i)
        if platform not in (0, 3):
            continue
        sub = base + offset
        fmt, = struct.unpack_from('>H', data, sub)
        if fmt == 4:
            segx2, = struct.unpack_from('>H', data, sub + 6)
            segs = segx2 // 2
            ends = struct.unpack_from('>%dH' % segs, data, sub + 14)
            starts = struct.unpack_from('>%dH' % segs, data, sub + 16 + segx2)
            deltas = struct.unpack_from('>%dh' % segs, data, sub + 16 + 2 * segx2)
            range_at = sub + 16 + 3 * segx2
            ranges = struct.unpack_from('>%dH' % segs, data, range_at)
            for s in range(segs):
                for c in range(starts[s], ends[s] + 1):
                    if c == 0xFFFF:
                        continue
                    if ranges[s] == 0:
                        glyph = (c + deltas[s]) & 0xFFFF
                    else:
                        at = range_at + 2 * s + ranges[s] + 2 * (c - starts[s])
                        glyph, = struct.unpack_from('>H', data, at)
                        if glyph:
                            glyph = (glyph + deltas[s]) & 0xFFFF
                    if glyph:
                        have.add(c)
        elif fmt == 12:
            groups, = struct.unpack_from('>I', data, sub + 12)
            for g in range(groups):
                start, end, glyph = struct.unpack_from('>III', data, sub + 16 + 12 * g)
                for c in range(start, end + 1):
                    if glyph + (c - start):
                        have.add(c)
    return have


def build(font_path):
    with open(font_path, 'rb') as f:
        data = f.read()
    sha = hashlib.sha256(data).hexdigest()
    if sha != FONT_SHA256:
        raise SystemExit('%s is not the recorded Barlow SemiBold: sha256 %s, not %s' % (font_path, sha, FONT_SHA256))
    have = cmap_characters(data)
    missing = [c for c in CHARACTERS if c not in have]
    if missing:
        raise SystemExit('Barlow SemiBold has no glyph for ' + ', '.join('U+%04X' % c for c in missing))

    font = ImageFont.truetype(font_path, PIXELS)
    ascent, descent = font.getmetrics()
    line_spacing = float(ascent + descent)

    # Each glyph drawn on its own canvas with its pen at (pad, ascent + pad),
    # then cut to its ink.
    pad = PIXELS
    glyphs = []
    for c in sorted(CHARACTERS):
        ch = chr(c)
        advance = font.getlength(ch)
        canvas = Image.new('L', (PIXELS * 3, ascent + descent + 2 * pad), 0)
        ImageDraw.Draw(canvas).text((pad, ascent + pad), ch, font=font, fill=255, anchor='ls')
        box = canvas.getbbox()
        if box is None:
            glyphs.append((c, None, 0.0, 0.0, advance))
            continue
        left, top, right, bottom = box
        ink = canvas.crop(box)
        x_offset = float(left - pad)
        y_offset = float(top - pad)
        x_advance = advance - x_offset - (right - left)
        glyphs.append((c, ink, x_offset, y_offset, x_advance))

    # Pack the ink left to right in rows, one pixel apart.
    x, y, row = 1, 1, 0
    placed = []
    for c, ink, xo, yo, xa in glyphs:
        if ink is None:
            placed.append((c, (0, 0, 0, 0), None, xo, yo, xa))
            continue
        w, h = ink.size
        if x + w + 1 > TEXTURE_WIDTH:
            x, y, row = 1, y + row + 1, 0
        placed.append((c, (x, y, x + w, y + h), ink, xo, yo, xa))
        x += w + 1
        row = max(row, h)
    height = y + row + 1

    texture = Image.new('L', (TEXTURE_WIDTH, height), 0)
    for c, rect, ink, xo, yo, xa in placed:
        if ink is not None:
            texture.paste(ink, rect[:2])
    alpha = texture.tobytes()
    texels = bytearray(len(alpha) * 4)
    for i, a in enumerate(alpha):
        texels[4 * i:4 * i + 4] = bytes((a, a, a, a))

    out = bytearray(b'DXTKfont')
    out += struct.pack('<I', len(placed))
    for c, rect, ink, xo, yo, xa in placed:
        out += struct.pack('<I4i3f', c, rect[0], rect[1], rect[2], rect[3], xo, yo, xa)
    out += struct.pack('<fI', line_spacing, DEFAULT_CHARACTER)
    out += struct.pack('<5I', TEXTURE_WIDTH, height, DXGI_FORMAT_R8G8B8A8_UNORM, TEXTURE_WIDTH * 4, height)
    out += texels
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description='Writes the Barlow SemiBold sprite font (#1317).')
    ap.add_argument('--font', default=FONT)
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    if not features.check('freetype2'):
        raise SystemExit('this Pillow has no FreeType, so it cannot draw the font')
    if not os.path.isfile(args.font):
        raise SystemExit(args.font + ' is not there: check out engine\\skymp (git submodule update --init engine/skymp) or pass --font')
    made = build(args.font)
    versions = 'Pillow %s, FreeType %s' % (Image.__version__, features.version('freetype2'))
    if args.check:
        try:
            with open(args.out, 'rb') as f:
                there = f.read()
        except OSError as e:
            print('FAIL  %s does not read: %s' % (args.out, e))
            return 1
        if there == made:
            print('PASS  %s is what this writes (%s)' % (args.out, versions))
            return 0
        print('FAIL  %s is not what this writes with %s (it was written with Pillow 12.3.0, FreeType 2.14.3)' % (args.out, versions))
        return 1
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'wb') as f:
        f.write(made)
    print('wrote %s: %d bytes, sha256 %s (%s)' % (args.out, len(made), hashlib.sha256(made).hexdigest(), versions))
    return 0


if __name__ == '__main__':
    sys.exit(main())
