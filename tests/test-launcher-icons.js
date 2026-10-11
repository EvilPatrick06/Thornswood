// test-launcher-icons.js
//
//     node tests/test-launcher-icons.js
//
// Three icon files, three jobs. launcher/app.ico is the Main launcher,
// the full Thornswood badge at every size. launcher/app-dev.ico is the
// Dev launcher, the TF monogram. site/public/favicon.ico is the website
// tab only, the crest. They must not share a frame.
//
// WHY THIS EXISTS. #1581 (5 Oct) put the favicon's crest into the 16, 24,
// 32, 48 and 64 frames of launcher/app.ico. Windows draws shortcuts and
// the taskbar from those small frames, so Main looked like the website
// tab. That shipped in 1.1.106 and 1.2.0. Djinn, 11 Oct 2026: Main is
// the badge at every size; the crest stays on the favicon; Dev stays
// the monogram.
//
// What it checks:
//   1. the three files are ICO files and app.ico has the seven sizes;
//   2. no frame payload in app.ico matches a frame in the favicon;
//   3. no frame payload in app.ico matches a frame in app-dev.ico;
//   4. a planted collision is found, so a comparison that always
//      returns nothing cannot pass.
//
// Read only.
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'launcher', 'app.ico');
const DEV = path.join(ROOT, 'launcher', 'app-dev.ico');
const FAV = path.join(ROOT, 'site', 'public', 'favicon.ico');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function u16(buf, off) { return buf.readUInt16LE(off); }
function u32(buf, off) { return buf.readUInt32LE(off); }

function readIco(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 6) throw new Error(file + ' is too short for an ICO header');
  const reserved = u16(buf, 0);
  const type = u16(buf, 2);
  const n = u16(buf, 4);
  if (reserved !== 0 || type !== 1) {
    throw new Error(file + ' is not an ICO (reserved=' + reserved + ' type=' + type + ')');
  }
  const frames = [];
  for (let i = 0; i < n; i++) {
    const o = 6 + i * 16;
    if (o + 16 > buf.length) throw new Error(file + ' directory is short at frame ' + i);
    const wByte = buf[o];
    const hByte = buf[o + 1];
    const size = u32(buf, o + 8);
    const off = u32(buf, o + 12);
    if (off + size > buf.length) {
      throw new Error(file + ' frame ' + i + ' payload runs past the file');
    }
    frames.push({
      w: wByte === 0 ? 256 : wByte,
      h: hByte === 0 ? 256 : hByte,
      size: size,
      payload: buf.slice(off, off + size)
    });
  }
  return { buf: buf, frames: frames };
}

function shared(aFrames, bFrames) {
  const hits = [];
  for (let i = 0; i < aFrames.length; i++) {
    for (let j = 0; j < bFrames.length; j++) {
      if (aFrames[i].payload.equals(bFrames[j].payload)) {
        hits.push({
          a: aFrames[i].w + 'x' + aFrames[i].h,
          b: bFrames[j].w + 'x' + bFrames[j].h
        });
      }
    }
  }
  return hits;
}

function sayHits(label, hits) {
  if (!hits.length) return label + ': none';
  return label + ': ' + hits.map(function (h) { return h.a + ' = ' + h.b; }).join(', ');
}

yes('launcher/app.ico is there', fs.existsSync(APP));
yes('launcher/app-dev.ico is there', fs.existsSync(DEV));
yes('site/public/favicon.ico is there', fs.existsSync(FAV));
if (!fs.existsSync(APP) || !fs.existsSync(DEV) || !fs.existsSync(FAV)) {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(1);
}

let app, dev, fav;
try {
  app = readIco(APP);
  yes('launcher/app.ico is an ICO', true);
} catch (e) {
  yes('launcher/app.ico is an ICO', false);
  console.log('  ' + e.message);
}
try {
  dev = readIco(DEV);
  yes('launcher/app-dev.ico is an ICO', true);
} catch (e) {
  yes('launcher/app-dev.ico is an ICO', false);
  console.log('  ' + e.message);
}
try {
  fav = readIco(FAV);
  yes('site/public/favicon.ico is an ICO', true);
} catch (e) {
  yes('site/public/favicon.ico is an ICO', false);
  console.log('  ' + e.message);
}
if (!app || !dev || !fav) {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(1);
}

const sizes = app.frames.map(function (f) { return f.w; }).join(',');
yes('launcher/app.ico has seven frames', app.frames.length === 7);
yes('those sizes are 16 24 32 48 64 128 256', sizes === '16,24,32,48,64,128,256');

const vsFav = shared(app.frames, fav.frames);
yes(sayHits('app.ico shares no frame with the favicon', vsFav), vsFav.length === 0);
if (vsFav.length) {
  vsFav.forEach(function (h) {
    console.log('  shared ' + h.a + ' with favicon ' + h.b);
  });
}

const vsDev = shared(app.frames, dev.frames);
yes(sayHits('app.ico shares no frame with app-dev.ico', vsDev), vsDev.length === 0);
if (vsDev.length) {
  vsDev.forEach(function (h) {
    console.log('  shared ' + h.a + ' with app-dev.ico ' + h.b);
  });
}

const vsSelf = shared(app.frames, app.frames);
yes('comparing app.ico to itself finds every frame (the reader is not a no-op)',
    vsSelf.length === app.frames.length);

const planted = app.frames.map(function (f) {
  return { w: f.w, h: f.h, size: f.size, payload: Buffer.from(f.payload) };
});
planted[0].payload = Buffer.from(fav.frames[0].payload);
const vsPlanted = shared(planted, fav.frames);
yes('a planted favicon frame inside a copy of app.ico is found', vsPlanted.length >= 1);

const self = fs.readFileSync(__filename, 'utf8');
yes('no em dash in this harness', self.indexOf('\u2014') < 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail > 0 ? 1 : 0);
