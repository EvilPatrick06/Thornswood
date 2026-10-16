// tests/test-2298-board-meshes.js
//
//     node tests/test-2298-board-meshes.js
//
// #2298: the notice board and the hold's drop box are Thornswood's own meshes,
// built from vanilla pieces by scripts/mods/Build-NoticeBoard.py, and
// Patrick's rule (12 Oct) is that clicking the board does only the board and
// clicking the box does only the box. This proves, without the game:
//
//   1. Both meshes are whole Skyrim SE NIFs: the header's version, the block
//      table adding up to the end of the file, one root, a BSFadeNode.
//   2. Every texture they name is one of the vanilla paths the build read, and
//      nothing in either file is the Missives board's (no missive). The other
//      server's short names, which its folder carried, are refused in every
//      tracked file by tests/test-other-server-name-gone.js.
//   3. Each has its own static collision, and none of the board's reaches over
//      the box where it stands beside the board; the box's covers only the box.
//   4. Thornswood-Content.esp's board names the new mesh, the drop box is a
//      separate object naming its own, and no record names the old mesh.
//   5. Go.ps1 writes both meshes and Ship-Rules.ps1 calls both ours.
//   6. E on the board or the box is the server's to answer, on its own
//      references (#2516): the client answers neither, so a press on the box
//      can never open the board. tests/test-2516-server-boards.js drives the
//      server's answer: the board opens only the board, the box only the box.
//
// What cannot be proven here is how the game's own crosshair meets that
// collision; that is the in game check on the issue's test task.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const REPO = path.join(__dirname, '..');
let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); }
}
const read = rel => fs.readFileSync(path.join(REPO, rel));
const HAVOK = 69.99125;
const BOARD = 'game/ours/Data/meshes/thornswood/noticeboard01.nif';
const BOX = 'game/ours/Data/meshes/thornswood/dropbox01.nif';
// Where the box's origin stands in the board's own space (Build-NoticeBoard.py says it).
const BOX_AT = [-134.52, 4.0, 80.0];

// ------------------------------------------------------------- a nif reader --
function readNif(b) {
  let o = b.indexOf(10) + 1;
  const nif = { b, version: b.readUInt32LE(o), user: b.readUInt32LE(o + 5), bsver: b.readUInt32LE(o + 13),
    types: [], blocks: [], strings: [] };
  const count = b.readUInt32LE(o + 9);
  o += 17;
  for (let i = 0; i < 3; i++) { o += 1 + b[o]; }
  const ntypes = b.readUInt16LE(o); o += 2;
  for (let i = 0; i < ntypes; i++) { const n = b.readUInt32LE(o); o += 4; nif.types.push(b.toString('latin1', o, o + n)); o += n; }
  const kinds = [];
  for (let i = 0; i < count; i++) { kinds.push(nif.types[b.readUInt16LE(o)]); o += 2; }
  const sizes = [];
  for (let i = 0; i < count; i++) { sizes.push(b.readUInt32LE(o)); o += 4; }
  const nstr = b.readUInt32LE(o); o += 8;
  for (let i = 0; i < nstr; i++) { const n = b.readUInt32LE(o); o += 4; nif.strings.push(b.toString('latin1', o, o + n)); o += n; }
  o += 4 + 4 * b.readUInt32LE(o);
  for (let i = 0; i < count; i++) { nif.blocks.push({ type: kinds[i], at: o, size: sizes[i] }); o += sizes[i]; }
  nif.roots = b.readUInt32LE(o);
  nif.root = b.readInt32LE(o + 4);
  nif.ends = o + 8 === b.length;
  return nif;
}

function textures(nif) {
  const out = [];
  for (const k of nif.blocks.filter(x => x.type === 'BSShaderTextureSet')) {
    let o = k.at;
    const n = nif.b.readUInt32LE(o); o += 4;
    for (let i = 0; i < n; i++) {
      const len = nif.b.readUInt32LE(o); o += 4;
      const s = nif.b.toString('latin1', o, o + len); o += len;
      if (s) { out.push(s.toLowerCase()); }
    }
    yes('  a texture set reads to its size', o === k.at + k.size);
  }
  return out;
}

// Corners of every bhkConvexVerticesShape, in game units.
function hulls(nif) {
  return nif.blocks.filter(x => x.type === 'bhkConvexVerticesShape').map(k => {
    let o = k.at + 32;
    const n = nif.b.readUInt32LE(o); o += 4;
    const v = [];
    for (let i = 0; i < n; i++) {
      v.push([0, 1, 2].map(j => nif.b.readFloatLE(o + 4 * j) * HAVOK));
      o += 16;
    }
    return v;
  });
}

const VANILLA = new Set([
  'textures\\clutter\\stockade\\stockadeplanks01.dds', 'textures\\clutter\\stockade\\stockadeplanks01_n.dds',
  'textures\\clutter\\stockade\\stockadeextra01.dds', 'textures\\clutter\\stockade\\stockadeextra01_n.dds',
  'textures\\clutter\\stockade\\stockadewood01.dds', 'textures\\clutter\\stockade\\stockadewood01_n.dds',
  'textures\\architecture\\windhelm\\whwoodboardsinterior01.dds', 'textures\\architecture\\windhelm\\whwoodbase01_n.dds',
  'textures\\dungeons\\ships\\shiproof01.dds', 'textures\\dungeons\\ships\\shiproof01_n.dds',
  'textures\\dungeons\\ships\\shipwoodside01.dds', 'textures\\dungeons\\ships\\shipwoodside01_n.dds',
  'textures\\architecture\\edgetrim\\woodedgetrim01.dds', 'textures\\architecture\\edgetrim\\woodedgetrim01_n.dds',
  'textures\\clutter\\common\\lampgeneric01.dds', 'textures\\clutter\\common\\lampgeneric01_n.dds',
  'textures\\dungeons\\candles01.dds', 'textures\\dungeons\\candles01_n.dds', 'textures\\dungeons\\candles01_g.dds',
  'textures\\clutter\\books\\note01.dds', 'textures\\clutter\\books\\note01_n.dds', 'textures\\clutter\\books\\note02.dds',
  'textures\\clutter\\books\\note03.dds', 'textures\\clutter\\books\\note03_n.dds', 'textures\\clutter\\books\\note04.dds',
  'textures\\clutter\\books\\tornpage.dds', 'textures\\clutter\\books\\tornpage_n.dds', 'textures\\clutter\\books\\tornpagetext.dds',
  'textures\\architecture\\solitude\\snail01.dds', 'textures\\architecture\\solitude\\snail01_n.dds',
  'textures\\clutter\\common\\strongbox.dds', 'textures\\clutter\\common\\strongbox_n.dds'
]);
const norm = t => (t.startsWith('textures\\') ? t : 'textures\\' + t);

// ------------------------------------------------------------- 1, 2 and 3 --
const meshes = {};
for (const [name, rel] of [['the board', BOARD], ['the drop box', BOX]]) {
  const b = read(rel);
  const nif = readNif(b);
  meshes[name] = nif;
  yes(name + ' is a Skyrim SE NIF (20.2.0.7, user 12, stream 100)',
      nif.version === 0x14020007 && nif.user === 12 && nif.bsver === 100);
  yes(name + ': its block table adds up to the end of the file, one root at block 0',
      nif.ends && nif.roots === 1 && nif.root === 0 && nif.blocks[0].type === 'BSFadeNode');
  yes(name + ' has static collision of its own',
      ['bhkCollisionObject', 'bhkRigidBody', 'bhkConvexVerticesShape'].every(t => nif.types.includes(t)) &&
      nif.b.readUInt8(nif.blocks.find(x => x.type === 'bhkRigidBody').at + 4) === 1);
  const tex = textures(nif);
  const odd = tex.filter(t => !VANILLA.has(norm(t)));
  yes(name + ' names only vanilla textures (' + tex.length + ' paths)', tex.length > 0 && odd.length === 0);
  if (odd.length) { console.log('      not on the list: ' + odd.join(', ')); }
  const low = b.toString('latin1').toLowerCase();
  yes(name + ' carries nothing of the Missives board', low.indexOf('missive') < 0);
}

{
  const boardHulls = hulls(meshes['the board']);
  const boxHulls = hulls(meshes['the drop box']);
  yes('the board has a collision box for each part but the notices (11)', boardHulls.length === 11);
  yes('the box has one, covering only the box', boxHulls.length === 1);
  const bx = boxHulls[0].map(v => [v[0] + BOX_AT[0], v[1] + BOX_AT[1], v[2] + BOX_AT[2]]);
  const lo = [0, 1, 2].map(i => Math.min(...bx.map(v => v[i])));
  const hi = [0, 1, 2].map(i => Math.max(...bx.map(v => v[i])));
  yes('the box, where it is placed, stands on the shelf (its bottom ' + lo[2].toFixed(1) + ')', Math.abs(lo[2] - 80) < 0.5);
  // A board hull reaches over the box when any part of it lies inside the box's
  // footprint above the shelf. Each hull is a box; test its corners and centre.
  const inside = p => p[0] > lo[0] + 0.5 && p[0] < hi[0] - 0.5 && p[1] > lo[1] + 0.5 && p[1] < hi[1] - 0.5 &&
                      p[2] > lo[2] + 0.5 && p[2] < hi[2] - 0.5;
  let over = 0;
  for (const h of boardHulls) {
    const c = [0, 1, 2].map(i => h.reduce((s, v) => s + v[i], 0) / h.length);
    if (h.some(inside) || inside(c)) { over++; }
    // and a hull that passes over the box's top, inside its footprint, is over it too
    const hlo = [0, 1, 2].map(i => Math.min(...h.map(v => v[i])));
    const hhi = [0, 1, 2].map(i => Math.max(...h.map(v => v[i])));
    const overlapsXY = hlo[0] < hi[0] && hhi[0] > lo[0] && hlo[1] < hi[1] && hhi[1] > lo[1];
    if (overlapsXY && hlo[2] < hi[2] + 40 && hhi[2] > lo[2] + 0.5) { over++; }
  }
  yes('no board collision reaches into or just over the box', over === 0);
}

// ---------------------------------------------------------------------- 4 --
{
  const esp = read('game/content/Thornswood-Content.esp');
  function records(buf) {
    const out = [];
    const hs = buf.readUInt32LE(4);
    (function walk(p, end) {
      while (p + 24 <= end) {
        const tag = buf.toString('latin1', p, p + 4);
        const size = buf.readUInt32LE(p + 4);
        if (tag === 'GRUP') { walk(p + 24, p + size); p += size; continue; }
        const flags = buf.readUInt32LE(p + 8);
        let data = buf.subarray(p + 24, p + 24 + size);
        if (flags & 0x40000) { data = zlib.inflateSync(data.subarray(4)); }
        out.push({ tag, fid: buf.readUInt32LE(p + 12), data });
        p += 24 + size;
      }
    })(24 + hs, buf.length);
    return out;
  }
  function sub(data, want) {
    for (let i = 0; i + 6 <= data.length;) {
      const t = data.toString('latin1', i, i + 4);
      const n = data.readUInt16LE(i + 4);
      if (t === want) { return data.subarray(i + 6, i + 6 + n); }
      i += 6 + n;
    }
    return null;
  }
  const z = b => (b ? b.toString('latin1').replace(/\0+$/, '') : '');
  const recs = records(esp);
  const board = recs.find(r => r.tag === 'ACTI' && r.fid === 0x0500593B);
  const box = recs.find(r => r.fid === 0x050154D0);
  yes('the board (ACTI 0500593B) names meshes\\thornswood\\noticeboard01.nif',
      !!board && z(sub(board.data, 'EDID')) === 'ThornswoodMessageBoard' &&
      z(sub(board.data, 'MODL')) === 'thornswood\\noticeboard01.nif');
  yes('  and its bounds are the new mesh\'s, not the old one\'s', !!board && (() => {
    const o = sub(board.data, 'OBND');
    return o && [0, 1, 2, 3, 4, 5].map(i => o.readInt16LE(2 * i)).join(',') === '-168,-71,0,140,71,246';
  })());
  yes('the drop box is an object of its own (050154D0, ThornswoodDropBox) on dropbox01.nif',
      !!box && z(sub(box.data, 'EDID')) === 'ThornswoodDropBox' && z(sub(box.data, 'MODL')) === 'thornswood\\dropbox01.nif');
  // Not a container: a container shows whoever opens it everything in it, and
  // Patrick's rule is that a person sees only what they put in (#2298).
  yes('  an activator, so E on it is answered by the box\'s own panel, never a container\'s',
      !!box && box.tag === 'ACTI');
  yes('no record names the old Missives board any more',
      !recs.some(r => r.data.toString('latin1').toLowerCase().indexOf('missiveboard') >= 0));
}

// ---------------------------------------------------------------------- 5 --
{
  const go = read('scripts/release/Go.ps1').toString();
  const rules = read('scripts/release/Ship-Rules.ps1').toString();
  for (const p of ['Data\\meshes\\thornswood\\noticeboard01.nif', 'Data\\meshes\\thornswood\\dropbox01.nif']) {
    yes('Go.ps1 writes ' + p + ' and Ship-Rules.ps1 calls it ours',
        go.indexOf("'" + p + "'") >= 0 && /\$ShipOursFiles = @\(([\s\S]*?)\n\)/.exec(rules)[1].indexOf("'" + p + "'") >= 0);
  }
}

// ---------------------------------------------------------------------- 6 --
{
  const front = read('game/plugins/thornswood-front.js').toString().replace(/\r\n/g, '\n');
  const gm = read('game/gamemode.js').toString().replace(/\r\n/g, '\n');
  yes('the client answers no press on the board or the box', front.indexOf('function boardPress(') < 0 &&
      front.indexOf('function boxPress(') < 0 && front.indexOf('function boardFacing(') < 0);
  yes('the server answers it, first in onActivate, on its own references',
      gm.indexOf('propBoard.boardActivated(refrId, casterRefrId)') > 0 &&
      gm.indexOf('propBoard.boardActivated(refrId, casterRefrId)') < gm.indexOf('WATER (#1382)'));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
