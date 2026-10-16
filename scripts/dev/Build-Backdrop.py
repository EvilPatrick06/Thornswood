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

The plate, game\\menu\\logo.nif. The menu draws the backdrop on the one shape
in Data\\meshes\\interface\\logo\\logo.nif. Until 16 Oct that file was a
wallpaper replacer's plate whose maker nobody recorded: a crumpled map shape
named CivilWarMap01 under a root whose author string was npurkeypile
(BACKDROP-SPEC.md, E.5). Patrick decided on 15 Oct (#2177) that Thornswood
builds its own, so --logo writes it here from the numbers below and nothing
else: one flat rectangle, four corners and two triangles, textured with
MAINMENUWALLPAPER.dds, with Skyrim's ordinary lighting shader settings and
no alpha property, since the picture is opaque. Nothing is read from the old
file. Its placement is: the root at scale 0.8, the plate moved by
PLATE_TRANSLATION, turned upright about x with the width and height scales
BACKDROP-SPEC.md measured (A), and at scale 1.42, with the half width and
half height below. Those are where and how big the menu drew the replacer's
plate, so the picture lands on screen where it did, and tests\\
test-menu-backdrop.js holds the drawn aspect to ASPECT. The one thing that
changed is depth: the replacer's map curled up to 5.3 units toward the edges,
and this plate is flat at the depth the map lay at.

The second plate. Skyrim's Anniversary Edition menu draws logo01ae.nif as
well as logo.nif, and both used to be the same plate, so the backdrop was
drawn twice. Deleting logo01ae.nif is no cure: the game then draws the
vanilla plate from Skyrim - Meshes1.bsa, a Bethesda logo over the backdrop.
And it cannot be an empty node either: the menu reads the first child of
logo01ae.nif's root as the logo's shape (the vanilla file is a BSFadeNode
over one BSTriShape), so a root with no children crashes the game at the
main menu (issue #1158: MistMenu, "mov rbx, [rax]" with rax 0, on the root
named CivilWarMap01, the replacer plate's). So game\\menu\\logo01ae.nif is
logo.nif with the plate hidden twice over: the shape carries the hidden flag
(APP_CULLED), so the renderer skips it without walking it, and the root's
scale is 0, so it is a point even if something clears that flag. The menu
finds the shape it reads, and there is one plate to draw.

Usage:
  python Build-Backdrop.py [<picture.png>] [<out.dds>]
  python Build-Backdrop.py --logo [<out.nif>]
  python Build-Backdrop.py --blank-logo [<out.nif>]

Defaults: launcher\\art\\thornswood-mainmenu-1535.png in, game\\menu\\
Mainmenuwallpaper.dds out; --logo writes game\\menu\\logo.nif; --blank-logo
reads game\\menu\\logo.nif and writes game\\menu\\logo01ae.nif, so after
--logo run --blank-logo too.

Needs Windows (texconv is a Windows program), Pillow (python -m pip install
pillow) and, the first time, the internet to fetch texconv. --logo and
--blank-logo need nothing but Python.
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

# The plate (--logo). Where the menu draws it: the replacer plate's placement,
# measured in BACKDROP-SPEC.md (A), so the backdrop lands where it did.
LOGO_TEXTURE = "textures\\interface\\objects\\MAINMENUWALLPAPER.dds"
ROOT_SCALE = 0.8
PLATE_TRANSLATION = (49.965, 0.0, -0.8438050746917725)
PLATE_WIDTH_SCALE = 0.9738960266113281   # BACKDROP-SPEC.md, width scale in matrix
PLATE_HEIGHT_SCALE = 0.8948038816452026  # and height scale in matrix
PLATE_SCALE = 1.42
HALF_WIDTH = 68.28512                    # the rectangle in the plate's own x
HALF_HEIGHT = 50.191174                  # and y, before the scales above
V_BOTTOM = (ROWS - 1) / TEX              # the picture's last row, 3004 of 4096
NIF_FLAGS = 524302                       # the flags Skyrim's static roots and shapes carry
# Skyrim's ordinary lighting shader: receive and cast shadows, own emit (black,
# so it adds nothing), remappable textures, z test; and z write, environment
# map light fade.
SHADER_FLAGS = (0x82400300, 0x00008001)
VERTEX_DESC = 0x0001B00000650407         # position, uv, normal, tangent: 28 bytes a vertex


def nif_blocks(b):
    """(type, offset, size) of every block of a Skyrim SE nif."""
    o = b.index(b"\n") + 1
    version, endian, user, blocks, bsver = struct.unpack_from("<IBIII", b, o)
    if version != 0x14020007 or user != 12 or bsver != 100:
        raise SystemExit("not a Skyrim SE nif (20.2.0.7, 12, 100)")
    o += 17
    for _ in range(3):                                  # author, process, export
        o += 1 + b[o]
    ntypes = struct.unpack_from("<H", b, o)[0]; o += 2
    types = []
    for _ in range(ntypes):
        n = struct.unpack_from("<I", b, o)[0]; o += 4
        types.append(b[o:o + n].decode("latin-1")); o += n
    kinds = struct.unpack_from("<%dH" % blocks, b, o); o += 2 * blocks
    sizes = struct.unpack_from("<%dI" % blocks, b, o); o += 4 * blocks
    nstr = struct.unpack_from("<I", b, o)[0]; o += 8
    for _ in range(nstr):
        o += 4 + struct.unpack_from("<I", b, o)[0]
    o += 4 + 4 * struct.unpack_from("<I", b, o)[0]    # groups
    out = []
    for i in range(blocks):
        out.append((types[kinds[i]], o, sizes[i]))
        o += sizes[i]
    return out


def av_fields(b, at):
    """Offsets of the flags and the scale of a NiAVObject block, and where
    the NiAVObject part ends (stream 100)."""
    o = at + 4                                          # name
    o += 4 + 4 * struct.unpack_from("<I", b, o)[0]      # extra data
    o += 4                                              # controller
    flags_at = o; o += 4
    o += 12 + 36                                        # translation, rotation
    scale_at = o; o += 4
    o += 4                                              # collision
    return flags_at, scale_at, o


def nif_string(s, width):
    """A length and the bytes: width 1 for the header's export strings (with
    a terminating zero, as Skyrim's files write them), 4 for the rest."""
    b = s.encode("ascii")
    if width == 1:
        b += b"\0"
        return struct.pack("<B", len(b)) + b
    return struct.pack("<I", len(b)) + b


def av_object(name, translation, rotation, scale):
    """NiObjectNET and NiAVObject as stream 100 writes them: the name, no
    extra data, no controller, the flags, the transform, no collision."""
    return (struct.pack("<iIiI", name, 0, -1, NIF_FLAGS) + struct.pack("<3f", *translation) +
            struct.pack("<9f", *rotation) + struct.pack("<fi", scale, -1))


def to_byte(v):
    """A -1 .. 1 component as Skyrim packs it into one byte."""
    return max(0, min(255, int(round((v + 1.0) * 127.5))))


def plate_logo():
    """game\\menu\\logo.nif: one flat textured rectangle, made from the
    numbers at the top of this file. Four blocks: the root, the shape, its
    shader and the shader's texture set."""
    strings = ["ThornswoodMenuBackdrop", "MenuBackdropPlate"]
    # Corners in the plate's own space, top left first, counter clockwise as
    # seen from +z, the side the menu looks at: U runs with x, V down the
    # picture, so the top edge samples row 0 and the bottom row 3004.
    corners = [(-HALF_WIDTH, HALF_HEIGHT, 0.0, 0.0), (-HALF_WIDTH, -HALF_HEIGHT, 0.0, V_BOTTOM),
               (HALF_WIDTH, -HALF_HEIGHT, 1.0, V_BOTTOM), (HALF_WIDTH, HALF_HEIGHT, 1.0, 0.0)]
    # Facing +z. Skyrim's vertices keep the direction U grows along in the
    # bitangent (+x, its x in the position's fourth float, y and z in the
    # normal's and tangent's fourth bytes) and the direction V grows along
    # in the tangent (-y).
    normal, tangent, bitangent = (0.0, 0.0, 1.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)
    verts = b""
    for x, y, u, v in corners:
        verts += struct.pack("<4f", x, y, 0.0, bitangent[0]) + struct.pack("<2e", u, v)
        verts += bytes([to_byte(normal[0]), to_byte(normal[1]), to_byte(normal[2]), to_byte(bitangent[1])])
        verts += bytes([to_byte(tangent[0]), to_byte(tangent[1]), to_byte(tangent[2]), to_byte(bitangent[2])])
    tris = struct.pack("<6H", 0, 1, 2, 2, 3, 0)
    radius = (HALF_WIDTH ** 2 + HALF_HEIGHT ** 2) ** 0.5
    # Upright: the plate's x stays x, its y becomes up (z) and its z faces
    # the menu's -y, each with its measured scale.
    rotation = (PLATE_WIDTH_SCALE, 0.0, 0.0,
                0.0, 0.0, -1.0,
                0.0, PLATE_HEIGHT_SCALE, 0.0)
    identity = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
    root = av_object(0, (0.0, 0.0, 0.0), identity, ROOT_SCALE) + struct.pack("<IiI", 1, 1, 0)
    shape = (av_object(1, PLATE_TRANSLATION, rotation, PLATE_SCALE) +
             struct.pack("<4f", 0.0, 0.0, 0.0, radius) +
             struct.pack("<iiiQHHI", -1, 2, -1, VERTEX_DESC, 2, 4, len(verts) + len(tris)) +
             verts + tris + struct.pack("<I", 0))
    shader = (struct.pack("<IiIi", 0, -1, 0, -1) + struct.pack("<II", *SHADER_FLAGS) +
              struct.pack("<2f2f", 0.0, 0.0, 1.0, 1.0) + struct.pack("<i", 3) +
              struct.pack("<3ff", 0.0, 0.0, 0.0, 1.0) +     # emissive colour and multiple
              struct.pack("<I", 3) +                        # wrap in both directions
              struct.pack("<fff", 1.0, 0.0, 80.0) +         # alpha, refraction, glossiness
              struct.pack("<3ff", 0.0, 0.0, 0.0, 1.0) +     # specular colour and strength
              struct.pack("<ff", 0.3, 2.0))                 # lighting effects 1 and 2
    textures = struct.pack("<I", 9) + nif_string(LOGO_TEXTURE, 4) + struct.pack("<I", 0) * 8
    blocks = [("BSFadeNode", root), ("BSTriShape", shape),
              ("BSLightingShaderProperty", shader), ("BSShaderTextureSet", textures)]
    kinds = []
    for k, _ in blocks:
        if k not in kinds:
            kinds.append(k)
    out = b"Gamebryo File Format, Version 20.2.0.7\n"
    out += struct.pack("<IBIII", 0x14020007, 1, 12, len(blocks), 100)
    out += nif_string("Thornswood", 1) + nif_string("", 1) + nif_string("", 1)
    out += struct.pack("<H", len(kinds)) + b"".join(nif_string(k, 4) for k in kinds)
    out += b"".join(struct.pack("<H", kinds.index(k)) for k, _ in blocks)
    out += b"".join(struct.pack("<I", len(b)) for _, b in blocks)
    out += struct.pack("<II", len(strings), max(len(s) for s in strings))
    out += b"".join(nif_string(s, 4) for s in strings) + struct.pack("<I", 0)
    out += b"".join(b for _, b in blocks) + struct.pack("<Ii", 1, 0)
    return out


def blank_logo(plate):
    """logo.nif with the plate hidden: the same blocks, so the Anniversary
    menu still finds the root's one shape child it reads (issue #1158), but
    the shape is flagged hidden (APP_CULLED, flag bit 0) and the root's scale
    is 0. Nothing is drawn, and the file still stops the game falling back to
    the vanilla plate."""
    b = bytearray(plate)
    blocks = nif_blocks(b)
    if blocks[0][0] != "BSFadeNode":
        raise SystemExit("logo.nif's root is %s, not BSFadeNode" % blocks[0][0])
    _, root_scale, root_end = av_fields(b, blocks[0][1])
    kids = struct.unpack_from("<I", b, root_end)[0]
    child = struct.unpack_from("<i", b, root_end + 4)[0] if kids else -1
    if kids != 1 or not (0 <= child < len(blocks)) or blocks[child][0] != "BSTriShape":
        raise SystemExit("logo.nif's root should have one BSTriShape child, the plate")
    struct.pack_into("<f", b, root_scale, 0.0)
    shape_flags, _, _ = av_fields(b, blocks[child][1])
    struct.pack_into("<I", b, shape_flags, struct.unpack_from("<I", b, shape_flags)[0] | 1)
    return bytes(b)


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
    if len(argv) > 1 and argv[1] == "--logo":
        out = Path(argv[2]) if len(argv) > 2 else MENU / "logo.nif"
        data = plate_logo()
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        print("wrote %s: one flat plate showing %s, %d bytes" % (out, LOGO_TEXTURE, len(data)))
        return 0

    if len(argv) > 1 and argv[1] == "--blank-logo":
        out = Path(argv[2]) if len(argv) > 2 else MENU / "logo01ae.nif"
        data = blank_logo((MENU / "logo.nif").read_bytes())
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        print("wrote %s: the plate, hidden and at scale 0, %d bytes" % (out, len(data)))
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
