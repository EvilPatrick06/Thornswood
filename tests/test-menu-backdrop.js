// test-menu-backdrop.js
//
//     node tests\test-menu-backdrop.js
//
// Issue #425: the main menu drew its backdrop twice, the picture was one mip
// level, and the build assumed a plane shape the mesh disagrees with. This
// reads the three files in game\menu with a small nif and dds reader and
// proves each half:
//
//   1. logo.nif is one plate: a single shape under its root, textured with
//      MAINMENUWALLPAPER.dds.
//   2. logo01ae.nif is there (deleting it brings the vanilla Anniversary plate
//      back) and is an empty node: no shape anywhere in it. So the menu has
//      exactly one shape to draw, not two. Until #425 it was a copy of the
//      plate with its root scale set to 0, still a shape in the scene.
//   3. The plate as drawn has the shape Build-Backdrop.py builds for: the
//      mesh's width over height, after its own rotation and scale, equals
//      ASPECT; its V reaches texel row 3004, so ROWS is 3005; its UVs are a
//      flat, straight mapping of the plate, so a centred crop at ASPECT
//      squeezed into 4096 x ROWS is the right picture.
//   4. Mainmenuwallpaper.dds is 4096 x 4096 with a full chain of 13 mip
//      levels, in a block format Skyrim SE draws (DXT1, DXT5 or BC7), sized
//      exactly for its levels, and rows 3005 to 4095 repeat the last picture
//      row instead of black. 4096 texels over the plate's 20/21 of the screen
//      width is at least one texel per screen pixel up to 3900 wide, so 1080p
//      to 4K is never magnified.
//   5. Build-Backdrop.py's default paths exist, and --blank-logo reproduces
//      logo01ae.nif byte for byte (needs python; SKIP without it).
//   6. Go.ps1 copies, and Ship-Rules.ps1 owns, the same three files.
//
// The source picture's size is reported, not failed: the artist's 4466 x 3016
// render is what makes the picture sharp, and it is outside the code.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = path.join(__dirname, '..');
const MENU = path.join(REPO, 'game', 'menu');
const BUILD = path.join(REPO, 'scripts', 'dev', 'Build-Backdrop.py');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

// ------------------------------------------------------------ nif reader --
// Skyrim SE only: 20.2.0.7, user version 12, stream version 100. Every block
// is located from the header's size table, so a block this does not parse is
// still counted and skipped correctly.
function readNif(file) {
  const b = fs.readFileSync(file);
  let o = b.indexOf(10) + 1;
  const nif = { bytes: b, version: b.readUInt32LE(o), user: b.readUInt32LE(o + 5),
    bsver: b.readUInt32LE(o + 13), types: [], blocks: [], strings: [] };
  const count = b.readUInt32LE(o + 9);
  o += 17;
  for (let i = 0; i < 3; i++) { o += 1 + b[o]; }
  const ntypes = b.readUInt16LE(o); o += 2;
  for (let i = 0; i < ntypes; i++) {
    const n = b.readUInt32LE(o); o += 4;
    nif.types.push(b.toString('latin1', o, o + n)); o += n;
  }
  const kinds = [];
  for (let i = 0; i < count; i++) { kinds.push(nif.types[b.readUInt16LE(o)]); o += 2; }
  const sizes = [];
  for (let i = 0; i < count; i++) { sizes.push(b.readUInt32LE(o)); o += 4; }
  const nstr = b.readUInt32LE(o); o += 8;
  for (let i = 0; i < nstr; i++) {
    const n = b.readUInt32LE(o); o += 4;
    nif.strings.push(b.toString('latin1', o, o + n)); o += n;
  }
  const groups = b.readUInt32LE(o); o += 4 + 4 * groups;
  for (let i = 0; i < count; i++) {
    nif.blocks.push({ index: i, type: kinds[i], at: o, size: sizes[i] });
    o += sizes[i];
  }
  const roots = b.readUInt32LE(o);
  nif.root = roots ? b.readInt32LE(o + 4) : -1;
  nif.endsWhereItShould = (o + 4 + 4 * roots === b.length);
  return nif;
}

// NiObjectNET + NiAVObject as stream 100 writes them.
function avObject(b, o) {
  const r = { name: b.readInt32LE(o) };
  o += 4;
  o += 4 + 4 * b.readUInt32LE(o);          // extra data
  o += 4;                                  // controller
  r.flags = b.readUInt32LE(o); o += 4;
  r.t = [0, 1, 2].map(i => b.readFloatLE(o + 4 * i)); o += 12;
  r.R = [0, 1, 2, 3, 4, 5, 6, 7, 8].map(i => b.readFloatLE(o + 4 * i)); o += 36;
  r.scale = b.readFloatLE(o); o += 4;
  o += 4;                                  // collision
  r.end = o;
  return r;
}

function children(nif, block) {
  const b = nif.bytes;
  const av = avObject(b, block.at);
  const n = b.readUInt32LE(av.end);
  const out = [];
  for (let i = 0; i < n; i++) { out.push(b.readInt32LE(av.end + 4 + 4 * i)); }
  return out;
}

const isShape = t => /TriShape|TriStrips/.test(t);
const isNode = t => /Node$/.test(t);

// Shapes reachable from the root, each with its scale along the way.
function drawn(nif) {
  const out = [];
  (function walk(i, scale) {
    if (i < 0 || i >= nif.blocks.length) { return; }
    const blk = nif.blocks[i];
    const av = avObject(nif.bytes, blk.at);
    if (isShape(blk.type)) { out.push({ block: blk, scale: scale * av.scale }); return; }
    if (isNode(blk.type)) { for (const c of children(nif, blk)) { walk(c, scale * av.scale); } }
  })(nif.root, 1);
  return out;
}

function half(u) {
  const s = u >> 15, e = (u >> 10) & 31, f = u & 1023;
  const v = e === 0 ? f / 1024 * Math.pow(2, -14) : (1 + f / 1024) * Math.pow(2, e - 15);
  return s ? -v : v;
}

// BSTriShape, stream 100: vertices, UVs, and the shader and texture it uses.
function triShape(nif, blk) {
  const b = nif.bytes;
  const av = avObject(b, blk.at);
  let o = av.end + 16 + 4;                 // bound, skin
  const shader = b.readInt32LE(o); o += 8; // shader, alpha
  const descLo = b.readUInt32LE(o); o += 8;
  o += 2;                                  // triangles
  const nv = b.readUInt16LE(o); o += 2;
  o += 4;                                  // data size
  const vsize = (descLo & 0xf) * 4;
  const uvAt = ((descLo >>> 8) & 0xf) * 4;
  const verts = [];
  for (let i = 0; i < nv; i++) {
    const p = o + i * vsize;
    verts.push({ x: b.readFloatLE(p), y: b.readFloatLE(p + 4), z: b.readFloatLE(p + 8),
      u: half(b.readUInt16LE(p + uvAt)), v: half(b.readUInt16LE(p + uvAt + 2)) });
  }
  // The first texture of the texture set the shader names. A
  // BSLightingShaderProperty is: shader type, name, extra data, controller,
  // two flag words, UV offset, UV scale, then the texture set.
  let texture = null;
  const sh = nif.blocks[shader];
  if (sh && sh.type === 'BSLightingShaderProperty') {
    const extra = b.readUInt32LE(sh.at + 8);
    const set = nif.blocks[b.readInt32LE(sh.at + 12 + 4 * extra + 4 + 8 + 16)];
    if (set && set.type === 'BSShaderTextureSet' && b.readUInt32LE(set.at) > 0) {
      const len = b.readUInt32LE(set.at + 4);
      texture = b.toString('latin1', set.at + 8, set.at + 8 + len);
    }
  }
  return { av, verts, texture };
}

// ------------------------------------------------------------ the meshes --
const LOGO = path.join(MENU, 'logo.nif');
const AE = path.join(MENU, 'logo01ae.nif');
yes('game\\menu\\logo.nif is there', fs.existsSync(LOGO));
yes('game\\menu\\logo01ae.nif is there (without it the vanilla Anniversary plate comes back)', fs.existsSync(AE));
if (!fs.existsSync(LOGO) || !fs.existsSync(AE)) { done(); }

const logo = readNif(LOGO);
const ae = readNif(AE);
for (const [name, nif] of [['logo.nif', logo], ['logo01ae.nif', ae]]) {
  yes(name + ' is a Skyrim SE nif (20.2.0.7, 12, 100)',
    nif.version === 0x14020007 && nif.user === 12 && nif.bsver === 100);
  yes(name + ' reads to its last byte (block sizes and footer add up)', nif.endsWhereItShould);
  yes(name + "'s root is a BSFadeNode", nif.root === 0 && nif.blocks[0].type === 'BSFadeNode');
}

const logoDrawn = drawn(logo);
const aeDrawn = drawn(ae);
const aeShapes = ae.blocks.filter(x => isShape(x.type)).length;
console.log('      shapes drawn: logo.nif ' + logoDrawn.length + ', logo01ae.nif ' + aeDrawn.length +
  ' (blocks: ' + logo.blocks.length + ' and ' + ae.blocks.length + ')');
yes('logo.nif draws one shape, at a scale above zero', logoDrawn.length === 1 && logoDrawn[0].scale > 0);
yes('logo01ae.nif holds no shape at all, so it draws nothing', aeShapes === 0 && aeDrawn.length === 0);
yes("logo01ae.nif's root has no children", children(ae, ae.blocks[0]).length === 0);
yes('the menu has one plate to draw, not two', logoDrawn.length + aeDrawn.length === 1);

// ------------------------------------------------------------- the plate --
const build = fs.readFileSync(BUILD, 'utf8');
const num = re => { const m = build.match(re); return m ? Number(m[1]) : NaN; };
const ASPECT = num(/^ASPECT = ([0-9.]+)/m);
const ROWS = num(/^ROWS = ([0-9]+)/m);
const TEX = num(/^TEX = ([0-9]+)/m);

const plate = triShape(logo, logoDrawn[0].block);
yes('the plate is textured with textures\\interface\\objects\\MAINMENUWALLPAPER.dds',
  /^textures\\interface\\objects\\mainmenuwallpaper\.dds$/i.test(plate.texture || ''));
const V = plate.verts;
const span = k => [Math.min(...V.map(p => p[k])), Math.max(...V.map(p => p[k]))];
const [x0, x1] = span('x'), [y0, y1] = span('y'), [u0, u1] = span('u'), [v0, v1] = span('v');
// Local x is the plate's width and local y its height; the shape's rotation
// carries the scale of each (column lengths of R), and its scale and the
// root's multiply both alike.
const R = plate.av.R;
const colX = Math.hypot(R[0], R[3], R[6]);
const colY = Math.hypot(R[1], R[4], R[7]);
const aspect = ((x1 - x0) * colX) / ((y1 - y0) * colY);
console.log('      plate as drawn: ' + ((x1 - x0) * colX).toFixed(4) + ' x ' + ((y1 - y0) * colY).toFixed(4) +
  ', aspect ' + aspect.toFixed(10) + '; Build-Backdrop.py ASPECT ' + ASPECT);
yes('the plate as drawn is Build-Backdrop.py\'s ASPECT (to 1e-6)', Math.abs(aspect - ASPECT) < 1e-6);
yes('the plate is not 3:2 (the old guess) and is 77:52 to 0.001 percent',
  Math.abs(aspect - 1.5) > 0.01 && Math.abs(aspect / (77 / 52) - 1) < 1e-5);
console.log('      UV: U ' + u0 + ' to ' + u1 + ', V ' + v0 + ' to ' + v1 + ' (row ' + (v1 * TEX) + ' of ' + TEX + ')');
yes('V reaches texel row 3004, so the picture fills ROWS = 3005 rows', v1 * TEX === 3004 && ROWS === 3005);
yes('U covers the whole texture width (within 3 texels at each edge)', u0 * TEX < 3 && (1 - u1) * TEX < 3);
// Flat, straight mapping: U follows x and V follows y linearly, to within the
// half-float the UVs are stored in (2 texels at 4096).
let worst = 0;
for (const p of V) {
  const du = u0 + (p.x - x0) / (x1 - x0) * (u1 - u0) - p.u;
  const dv = v0 + (y1 - p.y) / (y1 - y0) * (v1 - v0) - p.v;
  worst = Math.max(worst, Math.abs(du) * TEX, Math.abs(dv) * TEX);
}
console.log('      worst UV departure from a flat mapping: ' + worst.toFixed(3) + ' texels over ' + V.length + ' vertices');
yes('the UVs map the plate flat and straight (every vertex within 2 texels)', worst <= 2);

// ----------------------------------------------------------- the texture --
const DDS = path.join(MENU, 'Mainmenuwallpaper.dds');
yes('game\\menu\\Mainmenuwallpaper.dds is there', fs.existsSync(DDS));
if (!fs.existsSync(DDS)) { done(); }
const d = fs.readFileSync(DDS);
const h = d.readUInt32LE(12), w = d.readUInt32LE(16), mips = d.readUInt32LE(28);
const fourcc = d.toString('latin1', 84, 88);
const caps = d.readUInt32LE(108);
let format = fourcc, blockBytes = fourcc === 'DXT1' ? 8 : 16, start = 128;
if (fourcc === 'DX10') {
  const dxgi = d.readUInt32LE(128);
  format = dxgi === 98 ? 'BC7' : ('DXGI ' + dxgi);
  start = 148;
}
console.log('      texture: ' + w + ' x ' + h + ', ' + mips + ' mip levels, ' + format + ', ' + d.length + ' bytes');
yes('it is a DDS file', d.toString('latin1', 0, 4) === 'DDS ');
yes('it is 4096 x 4096 (TEX in Build-Backdrop.py)', w === 4096 && h === 4096 && TEX === 4096);
yes('it has the full chain: 13 mip levels', mips === 13 && mips === Math.log2(w) + 1);
yes('its header says so (DDSCAPS_MIPMAP and DDSCAPS_COMPLEX)', (caps & 0x400000) !== 0 && (caps & 0x8) !== 0);
yes('it is a block format Skyrim SE draws (DXT1, DXT5 or BC7)', ['DXT1', 'DXT5', 'BC7'].includes(format));
let expect = start;
for (let i = 0, s = w; i < mips; i++, s = Math.max(1, s >> 1)) { expect += Math.pow(Math.ceil(s / 4), 2) * blockBytes; }
yes('its size is exactly the header plus 13 levels (' + expect + ' bytes)', d.length === expect);
yes('4096 texels over 20/21 of the screen width is at least one per pixel at 3840 wide (4K)',
  w * 20 / 21 >= 3840);

// Rows ROWS-1 .. 4095 are the last picture row repeated. In block rows that
// is every block row from (ROWS-1)/4 down identical, column by column, and
// not black.
const bpr = w / 4;
const firstRepeat = Math.floor((ROWS - 1) / 4);
let same = true, black = true;
for (let br = firstRepeat; br < h / 4 && same; br++) {
  for (let bc = 0; bc < bpr; bc++) {
    const a = start + (firstRepeat * bpr + bc) * blockBytes;
    const bb = start + (br * bpr + bc) * blockBytes;
    if (d.compare(d, a, a + blockBytes, bb, bb + blockBytes) !== 0) { same = false; break; }
  }
}
for (let bc = 0; bc < bpr && black; bc++) {
  const a = start + (firstRepeat * bpr + bc) * blockBytes;
  if (d.readUInt16LE(a) !== 0 || d.readUInt16LE(a + 2) !== 0) { black = false; }
}
yes('below the picture, rows 3004 to 4095 repeat the last picture row', same);
yes('and that row is not black (no black bleeding up the mip levels)', !black);
// The last level, 1 x 1, is the average of the whole texture: not black.
yes('the smallest mip level is not black', d.readUInt16LE(d.length - blockBytes) !== 0);

// -------------------------------------------------------- the build script --
const art = path.join(REPO, 'launcher', 'art', 'thornswood-mainmenu-1535.png');
yes("Build-Backdrop.py's default picture is launcher\\art\\thornswood-mainmenu-1535.png",
  /DEFAULT_SRC = REPO \/ "launcher" \/ "art" \/ "thornswood-mainmenu-1535\.png"/.test(build) && fs.existsSync(art));
yes("Build-Backdrop.py writes into game\\menu by default",
  /^MENU = REPO \/ "game" \/ "menu"$/m.test(build) && /^DEFAULT_OUT = MENU \/ "Mainmenuwallpaper\.dds"$/m.test(build) &&
  /^REPO = HERE\.parent\.parent$/m.test(build));
if (fs.existsSync(art)) {
  const png = fs.readFileSync(art);
  const pw = png.readUInt32BE(16), ph = png.readUInt32BE(20);
  console.log('INFO  the source picture is ' + pw + ' x ' + ph + ', against the 4466 x 3016 the spec asks for (' +
    (4466 * 3016 / (pw * ph)).toFixed(1) + ' times the pixels): the menu stays soft until the artist\'s render is built');
}

const py = spawnSync('python', ['--version'], { encoding: 'utf8' });
if (py.error || py.status !== 0) {
  console.log('SKIP  --blank-logo reproduces logo01ae.nif (no python here)');
} else {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'backdrop-'));
  const out = path.join(tmp, 'logo01ae.nif');
  const r = spawnSync('python', [BUILD, '--blank-logo', out], { encoding: 'utf8' });
  const made = fs.existsSync(out) ? fs.readFileSync(out) : null;
  yes('Build-Backdrop.py --blank-logo reproduces game\\menu\\logo01ae.nif byte for byte',
    r.status === 0 && made && made.equals(ae.bytes));
  fs.rmSync(tmp, { recursive: true, force: true });
}

// ------------------------------------------------------ Go.ps1, Ship-Rules --
const go = fs.readFileSync(path.join(REPO, 'scripts', 'release', 'Go.ps1'), 'utf8');
const rules = fs.readFileSync(path.join(REPO, 'scripts', 'release', 'Ship-Rules.ps1'), 'utf8');
const three = ['Data\\meshes\\interface\\logo\\logo.nif', 'Data\\meshes\\interface\\logo\\logo01ae.nif',
  'Data\\textures\\interface\\objects\\Mainmenuwallpaper.dds'];
for (const rel of three) {
  const leaf = rel.split('\\').pop();
  yes('Go.ps1 copies game\\menu\\' + leaf + ' to ' + rel, go.includes("'" + leaf + "'") && go.includes("'" + rel + "'"));
  yes('Ship-Rules.ps1 counts ' + rel + ' as ours', rules.includes("'" + rel + "'"));
}

done();
