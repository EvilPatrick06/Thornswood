"""
Build-Backdrop.py

Turns a picture into the main menu backdrop texture,
Data\\textures\\interface\\objects\\Mainmenuwallpaper.dds.

How the menu plane works, measured on 2026-09-16 with a calibration grid:

  * The plane is drawn 105 percent of the screen WIDTH wide, whatever the
    resolution, and it does not care about the field of view setting.
  * It is shaped 3:2. So a 16:10 screen sees the middle 89 percent of its
    height, a 16:9 screen the middle 80 percent, a 21:9 ultrawide the middle
    60 percent. Width always fits. Keep the emblem and the title inside the
    middle 55 percent of the picture's height and they show on every monitor.
  * The mesh only reads the top 73.3 percent of the texture (V 0 to 0.733),
    so the picture goes into rows 0 to 3001 of a 4096x4096 texture and the
    rest stays black.
  * DXT1 with a conventional header. Pillow's own DDS writer leaves the
    linear size field wrong and the game then stretches the picture, so the
    header is written here by hand.

Usage:
  py Build-Backdrop.py <picture.png> [<out.dds>]

The picture is scaled evenly to cover 3:2 and cropped centred, the same way
Windows fills a desktop wallpaper. Any size works; bigger is sharper, and
below about 3000 pixels wide it will look soft on a 2560 wide screen.

Needs Pillow 11 or newer:  py -m pip install pillow
"""
import struct
import sys
from pathlib import Path

from PIL import Image

TEX = 4096
VMAX = 0.733
PLANE = (4096, 2731)  # 3:2

DEFAULT_OUT = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition"
                   r"\Data\textures\interface\objects\Mainmenuwallpaper.dds")


def fill(src, size):
    """Scale evenly until the picture covers size, then crop the middle."""
    sw, sh = src.size
    w, h = size
    s = max(w / sw, h / sh)
    im = src.resize((round(sw * s), round(sh * s)), Image.LANCZOS)
    x0 = (im.width - w) // 2
    y0 = (im.height - h) // 2
    return im.crop((x0, y0, x0 + w, y0 + h))


def write_dxt1(im, out):
    """Pillow encodes the blocks; the header is ours."""
    tmp = out.with_suffix(".tmp.dds")
    im.save(tmp, pixel_format="DXT1")
    raw = tmp.read_bytes()
    tmp.unlink()
    w, h = im.size
    linear = ((w + 3) // 4) * ((h + 3) // 4) * 8
    payload = raw[128:]
    if len(payload) != linear:
        raise SystemExit("DXT1 payload is %d bytes, expected %d" % (len(payload), linear))
    hdr = bytearray(128)
    hdr[0:4] = b"DDS "
    # size, flags (CAPS|HEIGHT|WIDTH|PIXELFORMAT|MIPMAPCOUNT|LINEARSIZE), h, w, linear size, depth, mips
    struct.pack_into("<7I", hdr, 4, 124, 0xA1007, h, w, linear, 0, 1)
    struct.pack_into("<II4sIIIII", hdr, 76, 32, 0x4, b"DXT1", 0, 0, 0, 0, 0)
    struct.pack_into("<4I", hdr, 108, 0x1000, 0, 0, 0)  # DDSCAPS_TEXTURE
    out.write_bytes(bytes(hdr) + payload)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    src = Image.open(argv[1]).convert("RGB")
    out = Path(argv[2]) if len(argv) > 2 else DEFAULT_OUT
    rows = round(VMAX * TEX)
    art = fill(src, PLANE).resize((TEX, rows), Image.LANCZOS)
    tex = Image.new("RGB", (TEX, TEX), (0, 0, 0))
    tex.paste(art, (0, 0))
    out.parent.mkdir(parents=True, exist_ok=True)
    write_dxt1(tex, out)
    print("wrote", out, "%dx%d DXT1, picture in rows 0 to %d" % (TEX, TEX, rows - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
