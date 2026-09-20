"""
Build-Backdrop.py

Turns a picture into the main menu backdrop texture,
Data\\textures\\interface\\objects\\Mainmenuwallpaper.dds, and writes it into
the repo at tools\\art\\menu, where Go.ps1 picks it up for every game folder
and Ship carries it to everybody.

The numbers are tools\\art\\BACKDROP-SPEC.md's, measured from logo.nif on
16 and 17 September, and they replace the 3:2 guess this script used to
carry:

  * The plane is drawn 1.4807558229 wide to 1 tall (77:52), not 3:2.
  * The mesh samples V from 0 to 751/1024, which on a 4096 texture is texel
    row 3004, so the picture fills rows 0 to 3004: 3005 rows.
  * Below row 3004 the texture must NOT be black. Black padding bleeds up
    into the picture at every mip level, so the last picture row is repeated
    to the bottom instead.
  * A full mip chain, 13 levels for 4096, because a single level is sampled
    at whatever the screen makes of it and reads soft at every size but its
    own. DXT1 throughout, the cheap option the spec allows.

The picture is scaled evenly to cover 77:52 and cropped centred, then fitted
to 4096 x 3005. Anything narrower than 4450 x 3005 is enlarged on the way;
the artist's deliverable is 4466 x 3016, and what is in the repo today is
1535 x 1024, so this is a soft build of the right picture until that
arrives.

Usage:
  py Build-Backdrop.py [<picture.png>] [<out.dds>]

Defaults: tools\\art\\thornswood-mainmenu-1535.png in, tools\\art\\menu\\
Mainmenuwallpaper.dds out.

Needs Pillow 11 or newer for the DXT1 encoder:  py -m pip install pillow
"""
import struct
import sys
from pathlib import Path

from PIL import Image

TEX = 4096
ROWS = 3005                      # V 0 .. 751/1024 on 4096, inclusive
ASPECT = 1.4807558229            # the plane as drawn, from logo.nif
HERE = Path(__file__).resolve().parent
DEFAULT_SRC = HERE / "art" / "thornswood-mainmenu-1535.png"
DEFAULT_OUT = HERE / "art" / "menu" / "Mainmenuwallpaper.dds"


def fill(src, aspect):
    """Crop the picture, centred, to the plane's aspect. No resampling here."""
    sw, sh = src.size
    if sw / sh > aspect:
        w = round(sh * aspect); h = sh
    else:
        w = sw; h = round(sw / aspect)
    x0 = (sw - w) // 2
    y0 = (sh - h) // 2
    return src.crop((x0, y0, x0 + w, y0 + h))


def dxt1_payload(im):
    """Pillow encodes the blocks; only the payload after its header is kept."""
    import io
    buf = io.BytesIO()
    im.save(buf, format="DDS", pixel_format="DXT1")
    raw = buf.getvalue()
    w, h = im.size
    linear = max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 8
    payload = raw[128:]
    if len(payload) != linear:
        raise SystemExit("DXT1 payload for %dx%d is %d bytes, expected %d" % (w, h, len(payload), linear))
    return payload


def main(argv):
    src_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_SRC
    out = Path(argv[2]) if len(argv) > 2 else DEFAULT_OUT
    src = Image.open(src_path).convert("RGB")
    if src.width < 4450 or src.height < 3005:
        print("note: %s is %dx%d, below the 4450x3005 floor, so the picture is enlarged %.2fx and will read soft"
              % (src_path.name, src.width, src.height, TEX / min(src.width, src.height * ASPECT)))

    art = fill(src, ASPECT).resize((TEX, ROWS), Image.LANCZOS)
    tex = Image.new("RGB", (TEX, TEX))
    tex.paste(art, (0, 0))
    # The last picture row, repeated to the bottom, so no mip level blends
    # black into the picture's lower edge.
    last = art.crop((0, ROWS - 1, TEX, ROWS))
    for y in range(ROWS, TEX):
        tex.paste(last, (0, y))

    levels = []
    im = tex
    while True:
        levels.append(dxt1_payload(im))
        if im.width == 1 and im.height == 1:
            break
        im = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)
    mips = len(levels)

    linear0 = ((TEX + 3) // 4) * ((TEX + 3) // 4) * 8
    hdr = bytearray(128)
    hdr[0:4] = b"DDS "
    # size, flags CAPS|HEIGHT|WIDTH|PIXELFORMAT|MIPMAPCOUNT|LINEARSIZE, h, w, linear size, depth, mips
    struct.pack_into("<7I", hdr, 4, 124, 0x000A1007, TEX, TEX, linear0, 0, mips)
    struct.pack_into("<II4sIIIII", hdr, 76, 32, 0x4, b"DXT1", 0, 0, 0, 0, 0)
    # DDSCAPS_COMPLEX | DDSCAPS_TEXTURE | DDSCAPS_MIPMAP
    struct.pack_into("<4I", hdr, 108, 0x8 | 0x1000 | 0x400000, 0, 0, 0)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(bytes(hdr) + b"".join(levels))
    print("wrote %s: %dx%d DXT1, %d mip levels, picture in rows 0 to %d, %s bytes"
          % (out, TEX, TEX, mips, ROWS - 1, format(out.stat().st_size, ",")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
