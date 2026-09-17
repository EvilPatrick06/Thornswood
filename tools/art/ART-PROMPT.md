# Thornswood main menu backdrop: what to ask the image generator for

Paste the block below into the generator as the prompt. The numbers in the
second block are the technical requirements; give those too if it accepts them,
otherwise resize and check the safe zone afterwards.

## Prompt

Wide landscape illustration for a Skyrim style fantasy game main menu, aspect
ratio 3:2. A large ornate emblem of intertwined dragons and thorns sits exactly
in the centre of the picture with the single word "Thornswood" beneath it in
carved silver runic lettering, together filling about half of the picture's
height. Around it a sweeping Nordic landscape: a sunrise over misty forested
valleys and a river on the left, snow capped mountains with a ruined stone
fortress and waterfalls on the right, a dragon in flight in the upper left sky,
thorny vines with green leaves and glowing purple crystals in the foreground
corners. Painterly, detailed, dramatic light, teal and gold palette. No other
text, no watermark, no border or frame around the edge, no vignette, no
darkened edges. The top fifth and the bottom fifth of the picture are pure sky
and foreground scenery with nothing important in them, so they can be cropped.

## Requirements

Aspect ratio 3:2 exactly (for example 4096 x 2731, 3600 x 2400, 3000 x 2000).
Bigger is sharper; below 3000 pixels wide it looks soft on a 2560 wide screen.
The game texture is 4096 wide, so 4096 x 2731 is the sweet spot.

Format PNG, sRGB, no JPEG artefacts.

Safe zone: the emblem, the title and anything else that matters must sit
inside the middle 55 percent of the height (between 22 percent and 78 percent
from the top) and inside the middle 80 percent of the width. Reason: the menu
plane is 3:2 and always fills the screen's width, so a 16:10 screen shows the
middle 89 percent of the height, a 16:9 screen the middle 80 percent, a 21:9
ultrawide the middle 60 percent. Whatever is outside that band is scenery
that gets cropped on wider screens and nobody misses it.

No frame or border around the picture. The current banner has a thorn frame
along all four edges; on a 16:9 or 21:9 screen the top and bottom of that frame
are cut off and the sides are not, which looks wrong. Thorns and leaves in the
corners are fine, a continuous border is not.

No vignette or edge darkening. The plane hangs a few percent past the screen
edge, so a darkened border shows up unevenly.

## What happens next

Drop the PNG on me or run tools\Build-Backdrop.py <picture.png> and it becomes
Data\textures\interface\objects\Mainmenuwallpaper.dds (4096 x 4096 DXT1, picture
in the top 73 percent, which is the part of the texture the menu mesh reads).
