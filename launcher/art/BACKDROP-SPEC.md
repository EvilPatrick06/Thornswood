# Thornswood main menu backdrop: exact file specification

## What is built today

`scripts\dev\Build-Backdrop.py` builds the backdrop from `launcher\art\thornswood-mainmenu-1535.png` into `game\menu\Mainmenuwallpaper.dds`. `scripts\release\Go.ps1` copies it into every game folder as `Data\textures\interface\objects\Mainmenuwallpaper.dds`, and Ship carries it.

```
Dimensions       4096 x 4096
Format           BC7_UNORM behind a DX10 header (DXGI_FORMAT 98)
Mip levels       13, each made from the one above with Lanczos
Picture rows     0 through 3004 (3005 rows)
Rows 3005..4095  row 3004 repeated, not black
Alpha            255 everywhere
File size        22,369,796 bytes
```

The script crops the picture, centred, to the plane's drawn aspect, 1.4807558229, without resampling, then resizes it once with Lanczos to 4096 x 3005. It hands the 13 levels to Microsoft's texconv (DirectXTex `may2026`, fetched into `local\texconv` and run only when its sha256 is the pinned one), which compresses them on the processor, so every machine builds the same bytes. Section D has each step.

`tests\test-menu-backdrop.js` is the check. It reads `game\menu\logo.nif` and holds the plate shape to the script: the plate as drawn is `ASPECT`, its V reaches texel row 3004 so `ROWS` is 3005, and its UVs map it flat. It reads the texture's header for the 13 level chain, the format and the exact size, and decodes the BC7 pixels to prove that the rows under the picture repeat the last picture row and that no texel of the top level is at or below the plate's alpha test. `scripts\dev\Check-Backdrop.ps1 -Game <folder>` reads a game folder's two logo meshes and its texture (size, levels, format) against the repo's, read only.

Still open: the picture is 1535 x 1024, so the build enlarges it 2.70 times and the menu reads soft until the artist's 4466 x 3016 render is built (section A), and the questions in section E.

## How it got here

Sections A to D are the measurements of 16 and 17 Sep and the changes they asked for. A and B are measurements and still hold. C and D were work to do, and all of it is done: each item now says what was built, with the 16 Sep file or script beside it as the reason. On 16 Sep the build stretched a 1536 x 1024 picture 2.6666667 times across and 2.9316406 times down, and aimed at a 3:2 plane, while the mesh says 1.4807558229, so even a perfect 3:2 source was 1.2829 percent off before anything was resampled.

Two numbers below come from one agent's parse of logo.nif and one independent re-derivation of it, and one premise under section B was never verified by anybody. Both are called out where they matter.

---

## A. THE SOURCE PICTURE

### What to ask for

```
Width               4466 pixels
Height              3016 pixels
Aspect              77:52 = 1.4807692308
Format              PNG
Bit depth           8 bits per channel
Channels            3 (RGB), PNG colour type 2
Alpha               not allowed
Colour space        sRGB
Interlace           0 (non-interlaced)
Source of pixels    rendered or painted at this size, never an upscale of a smaller file
```

Absolute floor, below which the build enlarges:

```
4450 x 3005
```

### Why 3005 rows and not 3004

The mesh samples V from 0.0005602836609 to 0.7333984375. That maximum is exactly 751/1024, which on a 4096 texture is texel row 3004.000000. A bilinear fetch at 3004.0 blends rows 3003 and 3004, so row 3004 must carry picture, and counting from row 0 that is 3005 rows.

The mesh agent first wrote "4449 by 3004" and its checker marked that WRONG and self-contradictory: `round(0.7333984375 * 4096)` is 3004, which fills rows 0 through 3003 and leaves the last sampled row empty. The corrected figures are the checker's and are used throughout below.

### Why 4450 columns and not 4449

The picture is centre-cropped to the plane's drawn aspect before it is squeezed into the 4096 wide texture window. At 3005 rows that crop is

```
3005 x 1.4807558229 = 4449.671248 columns
```

so 4450. At 4449 the crop is a third of a column short and the resample enlarges.

### Why 1.4807558229 and not 1.5

Measured from `C:\Thornswood\Game\Data\meshes\interface\logo\logo.nif`, the only shape in the file, whose texture slot 0 is `textures\interface\objects\MAINMENUWALLPAPER.dds`:

```
model sheet            136.570236206 x 100.382347107   ratio 1.3605005277
width scale in matrix  0.9738960266113
height scale in matrix 0.8948038816452
as drawn               151.093916699 x 102.038374163   ratio 1.4807558229
```

The plane is 1.282945 percent narrower than the 3:2 the 16 Sep script and its docstring assumed. The nearest clean integer ratio is 77:52 at 0.000905 percent off, which is why the deliverable is 4466 x 3016 rather than the bare floor.

The same file was in the repo as `game\menu\logo.nif` (md5 `5c3cf588`) until 16 Oct. Since then `game\menu\logo.nif` is Thornswood's own plate, which `scripts\dev\Build-Backdrop.py --logo` writes from these same numbers: one flat rectangle of the model sheet's size, with the two matrix scales, so it draws at the same 1.4807558229 (#2177). `tests\test-menu-backdrop.js` reads that aspect from it to 1e-6.

This rests on the NIF Matrix33 convention. The first agent's proof of that convention was circular and its checker marked it WRONG, then proved the same conclusion properly against `meshes\landscape\trees\treepineforestlog01.nif`, where one block has identity rotation and gives an unambiguous world box. So the value stands, but on the second proof, not the first.

### Aspect tolerance

The build centre-crops to the exact aspect. A source wider than 1.4807558229 loses columns off both sides, a taller one loses rows off the top and bottom. At 4466 x 3016 the loss is zero. If you must deliver exact 3:2 instead, the floor rises to 4508 x 3005 and the build discards 58 columns.

### What is in the repo today

The picture the build uses by default since 20 Sep, read from its own header on 5 Oct:

```
launcher\art\thornswood-mainmenu-1535.png
  1535 x 1024
  bit depth 8, colour type 2, interlace 0
  3,132,374 bytes
  aspect 1.4990234
  chunks: IHDR 13, caBX 23650, 48 IDAT, IEND 0
  no gAMA, no iCCP, no sRGB chunk
```

What the build does to it:

```
crop         1516 x 1024, centred: 9 columns off the left, 10 off the right
horizontal   4096 / 1516            = 2.7018470
vertical     3005 / 1024            = 2.9345703
area                                = 7.9287599
```

Against the floor:

```
2.8990228 times too narrow
2.9345703 times too short
8.5073862 times too few pixels
```

The picture measured on 16 Sep is still in the folder, and nothing builds from it:

```
launcher\art\thornswood-art-1536.png
  1536 x 1024          (IHDR bytes 00 00 06 00 / 00 00 04 00, read directly)
  bit depth 8, colour type 2, interlace 0
  3,525,902 bytes
  aspect exactly 1.5
  chunks: IHDR 13, caBX 23617, IDAT 3502216, IEND 0
  no gAMA, no iCCP, no sRGB chunk
```

What the 16 Sep build did to it, and how far it was from the floor:

```
horizontal   4096 / 1536 = 8/3      = 2.6666667
vertical     3002 / 1024 = 1501/512 = 2.9316406
area                                = 7.8177083

2.8971354 times too narrow
2.9345703 times too short
8.5018476 times too few pixels
```

The `caBX` chunk in both is C2PA content credentials. The build discards it.

Two earlier recommendations are superseded and should not be sent to anyone: 4608 x 3072 and 6144 x 4096. Both are exact 3:2 and both inherit the 16 Sep docstring's 3:2 assumption that the mesh refutes.

---

## B. THE SAFE ZONE

**Everything in this section rests on one unverified premise:** the plane is drawn at 105 percent of screen width, whatever the resolution. It came from one place, the 16 Sep `Build-Backdrop.py` docstring at line 9, and the docstring was rewritten on 20 Sep without it; today it is only here, in ART-PROMPT.md, and as 20/21 in a texel count in `tests\test-menu-backdrop.js`. There is no main menu NIF placement to check it against, and the menu itself is `interface\startmenu.swf`. Nobody across four agents and four checkers could verify it. See section E.

Taking it as given, with the measured plane aspect P = 1.4807558229 and screen aspect A:

```
visible width fraction   = 20/21 = 95.2381 percent, at every aspect
visible height fraction  = P / (1.05 A)
```

| screen | A | height visible |
|---|---|---|
| 4:3 | 1.333333 | 105.7683 pct (letterboxes) |
| 5:4 | 1.250000 | 112.8195 pct (letterboxes) |
| 16:10, 1920x1200 | 1.600000 | 88.1402 pct |
| 3:2 | 1.500000 | 94.0162 pct |
| 16:9 | 1.777778 | 79.3262 pct |
| 2560x1080 | 2.370370 | 59.4947 pct |
| 3440x1440 | 2.388889 | 59.0335 pct |
| 3840x1600 | 2.400000 | 58.7602 pct |
| 32:9 5120x1440 | 3.555556 | 39.6631 pct |

The 16 Sep docstring's 89 / 80 / 60 were computed from the 3:2 assumption. Corrected they are 88.14 / 79.33 / 58.76, and the 21:9 figure is the worst case of the family, not 2560x1080's 59.49.

### Safe rectangle, 16:10 through 21:9, on a 4466 x 3016 source

Binding case is 3840x1600 at A = 2.4.

```
left    107
top     622
right   4359
bottom  2394
size    4252 x 1772 pixels
        95.2079 pct of the width, 58.7533 pct of the height
```

### Tighter rectangle that also survives 32:9

```
left    107
top     910
right   4359
bottom  2106
size    4252 x 1196 pixels
        95.2079 pct of the width, 39.6552 pct of the height
```

Cost of covering 32:9: 576 rows, 288 off the top and 288 off the bottom.

All four edges are rounded inward, so the rectangles are never larger than the true visible area.

### What must sit inside it

The emblem, the title wordmark, any readable text, any face or focal object, and any element whose loss changes the composition. Sky, terrain, atmosphere and vignette are expected to run to the edges and be cut.

The 16 Sep docstring's "middle 55 percent of the height" still holds through 21:9, with 1.8801 points of margin per edge, which is 56.70 pixels on a 3016 tall source. It does not hold at 32:9, where a 55 percent band overhangs by 7.6684 points per edge, 231.28 pixels. If 32:9 counts, the number is 39.66 percent, not 55.

The 16 Sep docstring's "middle 80 percent of the width" is needlessly tight. The true figure is 95.2381 percent at every aspect, so an 80 percent band throws away 340.30 pixels of visible picture on each side of a 4466 wide source.

### Letterboxing at 4:3 and 5:4

The plane is shorter than the screen at these aspects, so bars appear. Fractions of the **screen** height left bare:

```
4:3   5.4537 pct total, 2.7268 pct per edge
5:4  11.3628 pct total, 5.6814 pct per edge
```

The geometry agent reported 7.14 and 14.29 percent here. Its checker marked that WRONG: those are fractions of the plane, not of the screen, and the bare screen fraction is 1 - 1/f. The checker's values are the ones above.

---

## C. THE OUTPUT TEXTURE

Asked for on 17 Sep, and what `game\menu\Mainmenuwallpaper.dds` is since #994 (28 Sep):

```
Dimensions       4096 x 4096
Picture rows     0 through 3004 (3005 rows)
Rows 3005..4095  last picture row repeated, not black (see section D)
Format           BC7_UNORM   (DXGI_FORMAT 98 = 0x62)
Mip levels       13
Alpha            255 everywhere
File size        22,369,796 bytes
```

Alpha is not decorative. `NiAlphaProperty` on this shape has flags 0x12EC: blending off, alpha testing **on**, test greater-than, threshold 188. Any texel written with alpha at or below 188 is discarded by the engine.

BC7_UNORM, not BC7_UNORM_SRGB. This install carries 353 of the former and 2 of the latter, and both of those two are 512 x 512 decal glow maps.

Size is not an estimate. Every one of the 39 loose 4096 x 4096 BC7 files on this machine is exactly 22,369,796 bytes, and I read one of them (`textures\actors\character\female\femalebody_1.dds`) field by field as a working template. The built file came out at exactly that size, and `tests\test-menu-backdrop.js` holds it to the header plus 13 levels.

### Why BC7 rather than DXT1

BC1 endpoints are RGB565, so red and blue move in steps of 8.2258 out of 255. Decoding the file shipped on 16 Sep (DXT1, built from the 1536 picture) along y = 60, the sky's blue channel spans 41 units over 1024 texels, 0.0400390625 units per texel, and takes only 17 of the 42 available 8 bit values. The longest flat band measured is 204 texels, against 205.44 predicted from the endpoint spacing. BC7 mode 6 carries 7 bit endpoints plus a P-bit with 16 step interpolation, which puts the same gradient's band at 25 texels, 8.2 times narrower. (The original report said "14 value ladder" and "2,180 of 8,960 blocks"; the checker marked both WRONG. 17 distinct values and 2,475 blocks are the reproduced figures. The 204 and 205.44 both reproduce.) `tests\test-menu-backdrop.js` decodes the BC7 file along the same row and fails on a flat band of 64 texels or more; on the file built today the longest is 19.

### Exact header field values

The 16 Sep header, read from `C:\Thornswood\Game\Data\textures\interface\objects\Mainmenuwallpaper.dds`, against the header of the file built since #994, read from `game\menu\Mainmenuwallpaper.dds` on 5 Oct:

| offset | field | 16 Sep | built |
|---|---|---|---|
| 4 | dwSize | 0x0000007C | unchanged |
| 8 | dwFlags | 0x000A1007 | unchanged |
| 12 | dwHeight | 0x00001000 | unchanged |
| 16 | dwWidth | 0x00001000 | unchanged |
| 20 | dwPitchOrLinearSize | 0x00800000 | **0x01000000** |
| 24 | dwDepth | 0x00000000 | 0x00000001 (optional) |
| 28 | dwMipMapCount | 0x00000001 | **0x0000000D** |
| 80 | ddspf.dwFlags | 0x00000004 | unchanged |
| 84 | ddspf.dwFourCC | 0x31545844 'DXT1' | **0x30315844 'DX10'** |
| 108 | dwCaps | 0x00001000 | **0x00401008** |

Then a 20 byte DXT10 header at offset 128, which the 16 Sep file did not have:

```
128  dxgiFormat         0x00000062   (98, BC7_UNORM)
132  resourceDimension  0x00000003   (TEXTURE2D)
136  miscFlag           0x00000000
140  arraySize          0x00000001
144  miscFlags2         0x00000003   (DDS_ALPHA_MODE_OPAQUE)
```

The 17 Sep spec asked for 0 in `miscFlags2`. texconv writes 3, which marks the alpha opaque, and every texel's alpha is 255.

Payload starts at 148 instead of 128.

`dwPitchOrLinearSize` carries the top level only, which for BC7 at 4096 x 4096 is 1024 x 1024 blocks x 16 bytes = 16,777,216 = 0x01000000. `dwCaps` 0x00401008 is DDSCAPS_TEXTURE 0x1000 plus DDSCAPS_COMPLEX 0x8 plus DDSCAPS_MIPMAP 0x400000. `dwFlags` needs no change because 0x000A1007 already carries DDSD_MIPMAPCOUNT and DDSD_LINEARSIZE.

One correction to an earlier report: it called the 16 Sep header "internally inconsistent" for setting DDSD_MIPMAPCOUNT with a mip count of 1. Its checker marked that WRONG after fetching the Microsoft page: DDSCAPS_MIPMAP is optional and DDSCAPS_COMPLEX applies only to files with more than one surface, so the 16 Sep header was unconventional but correct. The fields above changed because the file gained 12 more levels and a new format, not because it was malformed.

### If BC7 is ruled out

Staying on DXT1 with a full chain, which is what shipped from 20 Sep until #994:

```
Format      DXT1
Mip levels  13
File size   11,184,952 bytes
Changes     dwMipMapCount 0x00000001 -> 0x0000000D
            dwCaps        0x00001000 -> 0x00401008
            nothing else
```

Cost against the 16 Sep file's 8,388,736 bytes: +2,796,216 for DXT1, +13,981,060 for BC7.

### Mip levels are worth the bytes

The texture is minified on every common screen. Texels per screen pixel at 105 percent plane width:

```
1920   2.0317
2560   1.5238
3440   1.1340
3840   1.0159
5120   0.7619
```

At 1920 the hardware wants mip 1, which the 16 Sep file did not have. The built file has all 13 levels.

### Known ceiling

4096 texels are one-to-one up to a 3900 pixel wide screen. At 5120 the texture itself is magnified 1.3125 times no matter what the artist delivers. Closing that means TEX at 8192, which is 33,554,560 bytes in DXT1 and a separate decision.

---

## D. THE SCRIPT

`scripts\dev\Build-Backdrop.py`. This section was written on 17 Sep as five changes to make, with the 16 Sep script's line numbers, and all five are made. Items 1 to 3, the 13 level chain and writing into the repo came on 20 Sep (f1372b0, before this repository's history starts; To Do List entry 203 in `docs\archive\todo-list-2026-09-25.md`). #987 pointed the default paths at `launcher\art` and `game\menu` on 28 Sep, and #994 made the texture BC7 through texconv the same day. Each item says what the script does now and what it replaced.

### 1. The constants

```python
TEX = 4096
ROWS = 3005                      # V 0 .. 751/1024 on 4096, inclusive
ASPECT = 1.4807558229            # the plane as drawn, from logo.nif
FORMAT = "BC7_UNORM"             # DXGI_FORMAT 98
```

They replaced `PLANE = (4096, 2731)` and `rows = round(VMAX * TEX)`. That rounding returns 3004 even with the measured VMAX of 751/1024, one row short of the 3005 the mesh samples; kept derived, the threshold would be `VMAX >= 3004.5 / 4096 = 0.7335205078125`. So `ROWS` is written out, and `tests\test-menu-backdrop.js` holds it to the mesh: V reaches texel row 3004 and `ROWS` is 3005.

### 2. One crop, one resample

`fill(src, aspect)` crops the middle of the picture to the plane's aspect and does not resample. The script then resizes once:

```python
art = fill(src, ASPECT).resize((TEX, ROWS), Image.LANCZOS)
```

The 16 Sep `fill` scaled the picture to cover 4096 x 2731, and a second resize stretched those 2731 rows to 3002, so 271 rows of vertical detail were thrown away and re-invented by Lanczos on every build, at every source size. With a 4466 x 3016 source the one resize reduces on both axes (0.9172 horizontal, 0.9964 vertical).

### 3. The padding

Rows 3005 to 4095 repeat the last picture row:

```python
last = art.crop((0, ROWS - 1, TEX, ROWS))
for y in range(ROWS, TEX):
    tex.paste(last, (0, y))
```

The 16 Sep build filled them with black. With mips that black is averaged into the bottom of the picture at every level, and even at mip 0 the last block row mixed picture with black: in the 16 Sep file the block row covering texel rows 3000 to 3003 had its top endpoint luminance dragged to 190, against 225 to 238 for the block rows above it. The mesh never samples below V 0.7334 at mip 0, so the repeat costs nothing. `tests\test-menu-backdrop.js` decodes the built file and checks that every block row from row 3004 down is the same and is picture, not black.

### 4. The format and the mip chain

Pillow writes neither BC7 nor a mip chain. So the script makes the 13 levels itself, each from the one above with Lanczos, writes them into one uncompressed R8G8B8A8_UNORM DDS named after the output (`rgba_dds`; texconv names its output after its input), and runs texconv:

```
texconv -nologo -y -nogpu -bc x -dx10 -f BC7_UNORM -m 13 -o <outdir> Mainmenuwallpaper.dds
```

texconv keeps a chain it is handed. `-nogpu` uses the processor's encoder, so every machine writes the same bytes, and `-bc x` is BC7's slowest, best search. texconv is DirectXTex `may2026`, fetched on first use from `TEXCONV_URL` into `local\texconv` (ignored by git) and run only when its sha256 is `TEXCONV_SHA256`; THIRD-PARTY.md records it. The script refuses its own output unless it is DX10, DXGI 98 and 13 levels. The file came out at 22,369,796 bytes, as section C predicted.

The 16 Sep script wrote one DXT1 level itself (`write_dxt1`), with a length check against the top level alone that would have rejected any chain. The 17 Sep proposal was to hand texconv a PNG with `-if CUBIC`. An uncompressed DDS went instead, so no PNG gamma note can move the colours and `-if CUBIC` is not needed.

What it needs: Windows (texconv is a Windows program), Pillow (`python -m pip install pillow`), and the internet the first time, to fetch texconv. On the shipping machine Pillow 11.3.0 is installed under `python`, not `py` (#988), and the script runs there. `--blank-logo` needs nothing but Python.

### 5. The default paths

```python
DEFAULT_SRC = REPO / "launcher" / "art" / "thornswood-mainmenu-1535.png"
DEFAULT_OUT = MENU / "Mainmenuwallpaper.dds"          # game\menu
```

The texture is written into the repo, where `scripts\release\Go.ps1` copies it into every game folder and `scripts\release\Ship-Rules.ps1` counts it as ours. The 16 Sep `DEFAULT_OUT` wrote a loose file straight into the Steam copy's `Data\textures\interface\objects`: it needed elevation, it went around Vortex, and it left no copy anywhere the repo tracks. That is how `logo.nif` came to be found with no record of where it came from (E.5).

---

## E. WHAT IS STILL UNKNOWN

**1. The 105 percent of screen width figure.** Unverified by four agents and four checkers. It came from one place, the 16 Sep `Build-Backdrop.py` docstring at line 9, recorded as measured on 2026-09-16 with a calibration grid, and that docstring was rewritten on 20 Sep without it. `logo.nif` holds four blocks (five until 16 Oct) and no camera, so nothing in the mesh places it on screen, and the menu is `interface\startmenu.swf`. Every percentage and every rectangle in section B scales with it. What would settle it: one dev channel build carrying a backdrop with a ruler burned into it, opened at a known resolution and counted. Nothing short of a run settles it.

**2. Whether the plane's world aspect is its screen aspect.** 1.4807558229 is measured from the mesh transform. Turning that into a screen shape assumes square pixels and a camera that is not anamorphic, looking at a plane that faces it. Nothing here tests that.

**3. Whether the engine honours a mip chain on this slot, and whether it applies a LOD bias.** Not verified. The built file carries all 13 levels; if the engine does not use them, 5,592,432 bytes of it sit idle.

**4. Whether BC7 loads for an interface texture in this install.** Measured: 353 BC7 files work here, including Cathedral Weathers' 13 sunset gradients at 4096 x 1024 with full chains and an 8192 x 4096 galaxy, which is the same job as this backdrop. Also measured: there is zero BC7 anywhere under `interface`, the only loose texture in that folder is this one, and vanilla `Skyrim - Interface.bsa` is 145 DXT3 and 2 DXT1 with no DX10 headers at all. One dev Ship and one look at the menu settles it; #994 stays open for that look.

### Settled since 17 Sep

**Where `logo.nif` came from** (was E.5). Its author string was `npurkeypile` and it was processed with SSE NIF Optimizer v3.0.10. None of the 157 Vortex staging folders held it, so it was dropped into the Steam Data folder by hand. On 17 Sep six copies were on that machine, five sharing md5 `5c3cf5882818bbb0bfe2eefec4344f2a` plus the quarantined one. From 20 Sep the repo carried it as `game\menu\logo.nif`, the same md5. On 15 Oct it was measured again: one crumpled map shape named `CivilWarMap01` (a vanilla shape name), 256 vertices up to 5.3 units deep, the usual wallpaper replacer pattern, and a search found no mod with it. Who made it was never found, so Patrick decided Thornswood builds its own (#2177): since 16 Oct `scripts\dev\Build-Backdrop.py --logo` writes `game\menu\logo.nif` as one flat plate at the same size and placement, and `--blank-logo` makes `logo01ae.nif` from that. Nothing of the replacer's file is in either.

**The texconv command line** (was E.5). texconv was not on the measuring machine, so no flag had been checked against its own help output. Settled on 28 Sep by #994: D.4 has the command that runs.

**Which of the mesh and the script is authoritative** (was E.6). They disagreed by 1.282945 percent. `logo.nif` was edited by hand on 16 Sep, two hours before the texture was built: 13 bytes changed, all inside the shape's translation and rotation (offsets 0x187 to 0x1B1), and the quarantined copy at `C:\Thornswood\_quarantine\20260916-0112` has no non-uniform scale at all and drew at 1.3605005277. Somebody was pushing the plane toward 3:2 by eye and stopped 1.283 percent short. There were two ways to close it: re-fit two floats in the mesh to make the plane exactly 3:2 and keep a 3:2 source, or leave the mesh and make the script match it. The script was made to match the mesh on 20 Sep (f1372b0), and `tests\test-menu-backdrop.js` holds `ASPECT` to the mesh to 1e-6, so changing either one alone turns it red.
