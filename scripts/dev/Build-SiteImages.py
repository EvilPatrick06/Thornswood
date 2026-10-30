"""
Build-SiteImages.py

Builds the pictures the public pages show at the sizes they are shown at,
from the full size art beside them in site/public (#3218).

    python scripts/dev/Build-SiteImages.py           writes them into site/public
    python scripts/dev/Build-SiteImages.py --check   writes nothing, exits 1 when
                                                     one is missing or stale

A Lighthouse run of thornswood.net on 21 Oct 2026 measured what the pages
sent against what they drew. logo.png, 192 by 192 and 88 KiB, is drawn in
the header at 28 pixels. banner.jpg, 1600 by 900 and 326 KiB, was the video's
poster, a JPEG at full size for every screen, even a phone 400 pixels across.

So these are made from them, as WebP, which every browser the site supports
reads:

    logo-28.webp, logo-56.webp, logo-84.webp    the header emblem at one, two
                                                and three device pixels to
                                                a CSS pixel (srcset ... 1x 2x 3x)
    banner-800.webp, banner-1200.webp,          the still under the hero video
    banner-1600.webp                            (srcset ... 800w 1200w 1600w)

The banner is quality 70: side by side with the JPEG at full size nothing
differs that the eye finds, and the hero lays a scrim and grain over it.

logo.png and banner.jpg stay: the structured data and Publish-Discord.ps1 name
logo.png by its address, and Go.ps1 copies banner.jpg into the game's menu.

The output is the same bytes for the same input (Pillow, no timestamps in
WebP), so --check can say whether a picture in the repository was built from
the art beside it. records/asset-provenance.json names each one as derived.

Pillow only. Never connects to anything.
"""
import io
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PUBLIC = os.path.normpath(os.path.join(HERE, '..', '..', 'site', 'public'))

# (output, source, width, height, quality)
BUILDS = [
    ('logo-28.webp', 'logo.png', 28, 28, 90),
    ('logo-56.webp', 'logo.png', 56, 56, 90),
    ('logo-84.webp', 'logo.png', 84, 84, 90),
    ('banner-800.webp', 'banner.jpg', 800, 450, 70),
    ('banner-1200.webp', 'banner.jpg', 1200, 675, 70),
    ('banner-1600.webp', 'banner.jpg', 1600, 900, 70),
]


def build(source, width, height, quality):
    with Image.open(os.path.join(PUBLIC, source)) as im:
        im = im.convert('RGBA' if im.mode in ('RGBA', 'LA', 'P') else 'RGB')
        if im.size != (width, height):
            im = im.resize((width, height), Image.LANCZOS)
        out = io.BytesIO()
        im.save(out, 'WEBP', quality=quality, method=6)
        return out.getvalue()


def main(argv):
    check = '--check' in argv
    stale = []
    for name, source, width, height, quality in BUILDS:
        data = build(source, width, height, quality)
        path = os.path.join(PUBLIC, name)
        have = open(path, 'rb').read() if os.path.exists(path) else None
        if have == data:
            print('same   ' + name)
            continue
        if check:
            stale.append(name)
            print('STALE  ' + name + ' is not what ' + source + ' builds')
            continue
        with open(path, 'wb') as f:
            f.write(data)
        print('wrote  ' + name + ' (' + str(len(data)) + ' bytes, from ' + source + ')')
    return 1 if stale else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
