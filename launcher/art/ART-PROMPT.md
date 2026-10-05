# Thornswood main menu backdrop: what to ask the image generator for

Corrected 17 September 2026 against the mesh. The numbers that were here before
were measured by eye against a calibration grid and several of them were wrong.
`BACKDROP-SPEC.md` beside this file carries every figure with its proof and its
header values. This file is the short version you hand to an artist.

Paste the block below into the generator as the prompt. Give it the requirements
too if it accepts them, otherwise resize and check the safe zone afterwards.

## Prompt

Wide landscape illustration for a Skyrim style fantasy game main menu, aspect
ratio 77:52, very close to 3:2. A large ornate emblem of intertwined dragons and
thorns sits exactly in the centre of the picture with the single word
"Thornswood" beneath it in carved silver runic lettering, together filling about
half of the picture's height. Around it a sweeping Nordic landscape: a sunrise
over misty forested valleys and a river on the left, snow capped mountains with a
ruined stone fortress and waterfalls on the right, a dragon in flight in the
upper left sky, thorny vines with green leaves and glowing purple crystals in the
foreground corners. Painterly, detailed, dramatic light, teal and gold palette.
No other text, no watermark, no border or frame around the edge, no vignette, no
darkened edges. The top fifth and the bottom fifth of the picture are pure sky
and foreground scenery with nothing important in them, so they can be cropped.

## Requirements

Deliver exactly:

    4466 x 3016 pixels
    PNG, 8 bits per channel, RGB, no alpha
    sRGB, not interlaced
    painted or rendered at this size, never upscaled from a smaller file

The floor below which the build has to enlarge the picture is 4450 x 3005.
Anything smaller is soft on every screen. The picture the build uses today,
`thornswood-mainmenu-1535.png`, is 1535 x 1024, which is 8.5 times too few
pixels.

The aspect is 77:52, which is 1.48077. It is NOT 3:2. The menu plane measured
from `meshes\interface\logo\logo.nif` is drawn at 1.4807558229, and a 3:2 picture
is 1.28 percent too wide, so the build crops 58 columns off it.

## Safe zone

The plane always fills the screen's width and is cropped top and bottom, by more
on a wider screen. On a 4466 x 3016 picture, everything that matters must sit
inside:

    left 107, top 622, right 4359, bottom 2394        (4252 x 1772)

That survives every screen from 16:10 through 21:9. If ultrawide 32:9 screens
count, use the tighter box instead, which costs 576 rows:

    left 107, top 910, right 4359, bottom 2106        (4252 x 1196)

Inside the box: the emblem, the wordmark, any readable text, any face or focal
object. Outside it: sky, terrain, atmosphere, anything you will not miss.

Horizontally the picture keeps 95.24 percent at every aspect, so the side margins
are thin. The old brief said to stay inside the middle 80 percent of the width,
which threw away 340 visible pixels on each side.

## What the old brief got wrong

    plane shape         said 3:2            is 1.4807558229
    16:10 sees          said 89 percent     is 88.14 percent
    16:9 sees           said 80 percent     is 79.33 percent
    21:9 sees           said 60 percent     is 58.76 percent
    safe height         said middle 55 pct  holds to 21:9 only, 39.66 pct at 32:9
    safe width          said middle 80 pct  is 95.24 percent

Every one of those came from assuming the plane is 3:2. It is not.

4:3 and 5:4 screens letterboxe: the plane is shorter than the screen, so bars
appear across 5.45 percent and 11.36 percent of the screen height.

## Still not settled

The plane is drawn at 105 percent of the screen width. That figure came from
the build script's 16 Sep docstring, measured by eye against a calibration grid,
and nothing has checked it since. Every percentage above scales with it. One dev
build with a ruler burned into the picture settles it.

## No frame, no vignette

The old banner had a thorn frame along all four edges. On a 16:9 or 21:9 screen
the top and bottom of that frame are cut off and the sides are not, which looks
wrong. Thorns and leaves in the corners are fine, a continuous border is not.
A darkened edge shows up unevenly for the same reason.

## What happens next

Run `python scripts\dev\Build-Backdrop.py <picture.png>` and it writes
`game\menu\Mainmenuwallpaper.dds`: cropped to 77:52, 4096 x 4096 BC7 with 13 mip
levels, the picture in the top 3005 rows. Go.ps1 copies it into every game
folder as `Data\textures\interface\objects\Mainmenuwallpaper.dds` and Ship
carries it. `BACKDROP-SPEC.md` says what the script needs (D.4) and how the
result is checked ("What is built today", at the top).
