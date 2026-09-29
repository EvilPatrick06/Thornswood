"""
Build-Backdrop.py

Turns a picture into the main menu backdrop texture,
Data\\textures\\interface\\objects\\Mainmenuwallpaper.dds, and writes it into
the repo at game\\menu, where Go.ps1 picks it up for every game folder
and Ship carries it to everybody.

The numbers are launcher\\art\\BACKDROP-SPEC.md's, measured from logo.nif on
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

The second plate. Skyrim's Anniversary Edition menu draws logo01ae.nif as
well as logo.nif, and both used to be the same plate, so the backdrop was
drawn twice. Deleting logo01ae.nif is no cure: the game then draws the
vanilla plate from Skyrim - Meshes1.bsa, a Bethesda logo over the backdrop.
So game\\menu\\logo01ae.nif is an empty node (issue #425): the same header
as logo.nif, one BSFadeNode with no children, and nothing to draw. It used
to be a copy of the plate with its root scale set to 0, which hid the plate
but left the shape in the scene for the engine to walk every frame.

Usage:
  python Build-Backdrop.py [<picture.png>] [<out.dds>]
  python Build-Backdrop.py --blank-logo [<out.nif>]

Defaults: launcher\\art\\thornswood-mainmenu-1535.png in, game\\menu\\
Mainmenuwallpaper.dds out; --blank-logo reads game\\menu\\logo.nif and writes
game\\menu\\logo01ae.nif.

Needs Pillow 11 or newer for the DXT1 encoder:  python -m pip install pillow
(--blank-logo needs nothing but Python.)
"""
import struct
import sys
from pathlib import Path

TEX = 4096
ROWS = 3005                      # V 0 .. 751/1024 on 4096, inclusive
ASPECT = 1.4807558229            # the plane as drawn, from logo.nif
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MENU = REPO / "game" / "menu"
DEFAULT_SRC = REPO / "launcher" / "art" / "thornswood-mainmenu-1535.png"
DEFAULT_OUT = MENU / "Mainmenuwallpaper.dds"


def blank_logo(plate):
    """An empty copy of the menu plate: logo.nif's header, one BSFadeNode
    with the same name and no children, root scale 0. Nothing to draw, and
    the file still stops the game falling back to the vanilla plate."""
    b = plate
    o = b.index(b"\n") + 1
    version, endian, user, blocks, bsver = struct.unpack_from("<IBIII", b, o)
    if version != 0x14020007 or user != 12 or bsver != 100:
        raise SystemExit("logo.nif is not a Skyrim SE nif (20.2.0.7, 12, 100)")
    head_start = o
    o += 17
    for _ in range(3):                                  # author, process, export
        o += 1 + b[o]
    export_info = b[head_start + 17:o]
    ntypes = struct.unpack_from("<H", b, o)[0]; o += 2
    types = []
    for _ in range(ntypes):
        n = struct.unpack_from("<I", b, o)[0]; o += 4
        types.append(b[o:o + n].decode("latin-1")); o += n
    first = struct.unpack_from("<H", b, o)[0]
    o += 2 * blocks + 4 * blocks
    nstr = struct.unpack_from("<I", b, o)[0]; o += 8
    n = struct.unpack_from("<I", b, o)[0]
    name = b[o + 4:o + 4 + n] if nstr else b""
    if types[first] != "BSFadeNode":
        raise SystemExit("logo.nif's root is %s, not BSFadeNode" % types[first])

    out = bytearray(b[:head_start])
    out += struct.pack("<IBIII", version, endian, user, 1, bsver) + export_info
    out += struct.pack("<HI", 1, 10) + b"BSFadeNode"
    node = struct.pack("<iIiI3f9ffiII",
                       0, 0, -1, 0x8000E,                # name, extra data, controller, flags
                       0.0, 0.0, 0.0,                    # translation
                       1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,
                       0.0,                              # scale
                       -1, 0, 0)                         # collision, children, effects
    out += struct.pack("<HI", 0, len(node))
    out += struct.pack("<III", 1, len(name), len(name)) + name
    out += struct.pack("<I", 0)                         # groups
    out += node
    out += struct.pack("<Ii", 1, 0)                     # one root, block 0
    return bytes(out)


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
    if len(argv) > 1 and argv[1] == "--blank-logo":
        out = Path(argv[2]) if len(argv) > 2 else MENU / "logo01ae.nif"
        data = blank_logo((MENU / "logo.nif").read_bytes())
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        print("wrote %s: one empty BSFadeNode, no shape, %d bytes" % (out, len(data)))
        return 0

    from PIL import Image

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
