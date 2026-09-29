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
    own.
  * BC7_UNORM, not DXT1 (issue #994). DXT1 keeps red and blue to 32 steps,
    so the sky's slow gradient comes out in bands about 200 texels wide;
    BC7 cuts them about eight times narrower (BACKDROP-SPEC.md, "Why BC7").
    UNORM and not UNORM_SRGB, because Skyrim SE reads its textures as the
    numbers they hold, the way it read the DXT1 file: the sRGB flag would
    have the card convert every texel on the way in and the picture would
    draw darker than it was built. The 353 BC7 textures in a full install
    are UNORM too, all but two small glow maps.

The mip levels are made here, each from the one above with Lanczos, and
Microsoft's texture converter, texconv, only compresses them: it keeps a chain
it is handed. Pillow cannot write BC7. texconv is not in the repo, the same as
the signing client: TEXCONV_URL is one pinned release, fetched on first use
into local\\texconv (ignored by git) and refused unless its sha256 is
TEXCONV_SHA256. It runs on the processor (-nogpu), so the same picture builds
the same file byte for byte on any machine. THIRD-PARTY.md records it.

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

Needs Windows (texconv is a Windows program), Pillow (python -m pip install
pillow) and, the first time, the internet to fetch texconv. --blank-logo
needs nothing but Python.
"""
import hashlib
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

TEX = 4096
ROWS = 3005                      # V 0 .. 751/1024 on 4096, inclusive
ASPECT = 1.4807558229            # the plane as drawn, from logo.nif
FORMAT = "BC7_UNORM"             # DXGI_FORMAT 98
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MENU = REPO / "game" / "menu"
DEFAULT_SRC = REPO / "launcher" / "art" / "thornswood-mainmenu-1535.png"
DEFAULT_OUT = MENU / "Mainmenuwallpaper.dds"

# DirectXTex may2026, texconv 2026.5.8.1, MIT, signed by Microsoft. A newer
# release is a new URL and a new sha256 here and in THIRD-PARTY.md together.
TEXCONV_URL = "https://github.com/microsoft/DirectXTex/releases/download/may2026/texconv.exe"
TEXCONV_SHA256 = "dcfdec10244e02cf5037fba089c55fb7e1326b1c8181742d77d15fa5cb5eef06"
TEXCONV = REPO / "local" / "texconv" / "may2026" / "texconv.exe"


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


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def texconv():
    """The pinned texconv, fetched once into local\\texconv. A copy whose
    sha256 is not TEXCONV_SHA256 is never run."""
    if TEXCONV.exists() and sha256(TEXCONV) == TEXCONV_SHA256:
        return TEXCONV
    TEXCONV.parent.mkdir(parents=True, exist_ok=True)
    part = TEXCONV.with_suffix(".part")
    print("fetching %s" % TEXCONV_URL)
    with urllib.request.urlopen(TEXCONV_URL, timeout=120) as r, open(part, "wb") as f:
        shutil.copyfileobj(r, f)
    got = sha256(part)
    if got != TEXCONV_SHA256:
        part.unlink()
        raise SystemExit("texconv.exe from %s has sha256 %s, not the pinned %s; not run"
                         % (TEXCONV_URL, got, TEXCONV_SHA256))
    part.replace(TEXCONV)
    return TEXCONV


def rgba_dds(levels):
    """An uncompressed R8G8B8A8_UNORM DDS holding every level, for texconv to
    compress. Alpha is 255 everywhere: the plate alpha tests at 188."""
    hdr = bytearray(128)
    hdr[0:4] = b"DDS "
    # CAPS|HEIGHT|WIDTH|PITCH|PIXELFORMAT|MIPMAPCOUNT, h, w, pitch, depth, mips
    struct.pack_into("<7I", hdr, 4, 124, 0x0002100F, TEX, TEX, TEX * 4, 0, len(levels))
    # RGB|ALPHAPIXELS, 32 bits, R G B A masks
    struct.pack_into("<II4sIIIII", hdr, 76, 32, 0x41, b"\0\0\0\0", 32,
                     0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000)
    # DDSCAPS_COMPLEX | DDSCAPS_TEXTURE | DDSCAPS_MIPMAP
    struct.pack_into("<4I", hdr, 108, 0x8 | 0x1000 | 0x400000, 0, 0, 0)
    return bytes(hdr) + b"".join(im.convert("RGBA").tobytes() for im in levels)


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

    levels = [tex]
    while levels[-1].width > 1:
        im = levels[-1]
        levels.append(im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS))
    mips = len(levels)

    exe = texconv()
    work_root = REPO / "local"
    work_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="backdrop-", dir=str(work_root)) as work:
        work = Path(work)
        # texconv names its output after its input.
        src_dds = work / "in" / out.name
        src_dds.parent.mkdir()
        src_dds.write_bytes(rgba_dds(levels))
        done = work / "out"
        done.mkdir()
        # -nogpu: the processor's encoder, the same bytes on every machine.
        # -bc x: BC7's slowest, best search. -m: keep the chain handed in.
        r = subprocess.run([str(exe), "-nologo", "-y", "-nogpu", "-bc", "x", "-dx10",
                            "-f", FORMAT, "-m", str(mips), "-o", str(done), str(src_dds)],
                           capture_output=True, text=True)
        made = done / out.name
        if r.returncode != 0 or not made.exists():
            raise SystemExit("texconv failed (%d):\n%s%s" % (r.returncode, r.stdout, r.stderr))
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(made, out)

    b = out.read_bytes()
    if b[84:88] != b"DX10" or struct.unpack_from("<I", b, 128)[0] != 98 or \
            struct.unpack_from("<I", b, 28)[0] != mips:
        raise SystemExit("%s is not BC7_UNORM with %d levels; texconv wrote something else" % (out, mips))
    print("wrote %s: %dx%d %s, %d mip levels, picture in rows 0 to %d, %s bytes"
          % (out, TEX, TEX, FORMAT, mips, ROWS - 1, format(len(b), ",")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
