'use strict';
/*
  test-515-site-looks.js

  #515: "Make the site yours". A visitor picks colours, a font and a weight
  once and every page remembers it. This checks the pieces that make that
  true rather than a screenshot:

  A. looks.js, run against a stand-in document and localStorage: defaults,
     a saved look, junk and unknown values, storage that throws, reset.
  B. Every page shell loads /looks.js in <head>, not deferred, before its
     first stylesheet (no flash of the default), and loads /looks.css.
  C. looks.css only redefines tokens a base :root declares, every palette
     sets the same tokens, and its selectors match looks.js's allowlist.
  D. No colour literal outside :root in home.css, hub.css or door.css unless
     it is marked "look: fixed" (text over the hero painting, Discord brand),
     so a new hand-written colour cannot quietly ignore the visitor's look.
*/
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const PUB = path.join(__dirname, '..', 'site', 'public');
const read = (f) => fs.readFileSync(f, 'utf8').split('\r\n').join('\n');
let pass = 0, fail = 0;
function yes(what, c) {
  if (c) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); }
}

const LOOKS_JS = read(path.join(PUB, 'looks.js'));
const LOOKS_CSS = read(path.join(PUB, 'looks.css'));

// ------------------------------------------------------------------- A
function page(opts) {
  opts = opts || {};
  const store = Object.assign({}, opts.store || {});
  const attrs = {};
  const meta = { content: '#0B0E0A', setAttribute(k, v) { this[k] = v; } };
  const listeners = {};
  const ls = {
    getItem(k) { if (opts.broken) throw new Error('denied'); return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
    setItem(k, v) { if (opts.broken) throw new Error('denied'); store[k] = String(v); },
    removeItem(k) { if (opts.broken) throw new Error('denied'); delete store[k]; },
  };
  const document = {
    documentElement: {
      setAttribute(k, v) { attrs[k] = String(v); },
      removeAttribute(k) { delete attrs[k]; },
    },
    querySelector(s) { return s === 'meta[name="theme-color"]' ? meta : null; },
    querySelectorAll() { return []; },
    addEventListener(t, f) { listeners['doc:' + t] = f; },
  };
  const window = { localStorage: ls, addEventListener(t, f) { listeners['win:' + t] = f; } };
  const ctx = { window, document, JSON };
  vm.runInNewContext(LOOKS_JS, ctx);
  return { attrs, store, meta, api: window.twLook, listeners };
}

let p = page();
yes('A1 nothing saved: no data- attribute, the site as designed', Object.keys(p.attrs).length === 0);
yes('A2 nothing saved: the bar colour stays Night', p.meta.content === '#0B0E0A');
yes('A3 the script publishes window.twLook', !!(p.api && p.api.save && p.api.read));

p = page({ store: { 'tw:look': JSON.stringify({ palette: 'parchment', font: 'plain', weight: 'heavier' }) } });
yes('A4 a saved look is on <html> as soon as the script runs',
  p.attrs['data-palette'] === 'parchment' && p.attrs['data-font'] === 'plain' && p.attrs['data-weight'] === 'heavier');
yes('A5 the bar colour follows the palette', p.meta.content === '#EFE9DA');

p = page({ store: { 'tw:look': JSON.stringify({ palette: 'javascript:alert(1)', font: 'book', weight: 7 }) } });
yes('A6 an unknown value falls back to the default, a known one beside it stays',
  p.attrs['data-palette'] === undefined && p.attrs['data-font'] === 'book' && p.attrs['data-weight'] === undefined);

p = page({ store: { 'tw:look': '{not json' } });
yes('A7 a broken saved value: the default, nothing thrown', Object.keys(p.attrs).length === 0);

let threw = false;
try { p = page({ broken: true }); } catch (e) { threw = true; }
yes('A8 storage that throws: the default, nothing thrown', !threw && Object.keys(p.attrs).length === 0);
threw = false;
try { p.api.save({ palette: 'contrast' }); } catch (e) { threw = true; }
yes('A9 saving with storage that throws still applies it to this page', !threw && p.attrs['data-palette'] === 'contrast');

p = page();
p.api.save({ palette: 'contrast', font: 'designed', weight: 'regular' });
yes('A10 saving stores one key, cleaned', JSON.parse(p.store['tw:look']).palette === 'contrast' && Object.keys(p.store).length === 1);
yes('A11 and a default part is no attribute', p.attrs['data-palette'] === 'contrast' && p.attrs['data-font'] === undefined);
p.api.save({});
yes('A12 back to the default removes the key and every attribute', p.store['tw:look'] === undefined && Object.keys(p.attrs).length === 0);
yes('A13 another tab changing the look is listened for', typeof p.listeners['win:storage'] === 'function');
yes('A14 the picker is built once the page is read', typeof p.listeners['doc:DOMContentLoaded'] === 'function');

const OPTIONS = page().api.OPTIONS;

// ------------------------------------------------------------------- B
function headOrder(name, html) {
  const head = (html.split('</head>')[0]) || '';
  const js = head.indexOf('<script src="/looks.js"></script>');
  const css = head.search(/<link rel="stylesheet"/);
  yes('B ' + name + ' loads /looks.js in <head>, plain (not defer or async)', js >= 0);
  yes('B ' + name + ' loads /looks.js before its first stylesheet', js >= 0 && css >= 0 && js < css);
  yes('B ' + name + ' loads /looks.css', /<link rel="stylesheet" href="\/looks\.css">/.test(head));
}
headOrder('home.html', read(path.join(PUB, 'home.html')));
headOrder('index.html (the hub)', read(path.join(PUB, 'index.html')));
const SERVER = read(path.join(__dirname, '..', 'site', 'server.js'));
const doorLinks = SERVER.split('href="/door.css"').length - 1;
const doorWith = SERVER.split('<script src="/looks.js"></script><link rel="stylesheet" href="/door.css"><link rel="stylesheet" href="/looks.css">').length - 1;
yes('B every door page server.js writes loads looks.js first and looks.css (' + doorWith + '/' + doorLinks + ')', doorLinks > 0 && doorWith === doorLinks);
yes('B home.html has the picker in it', /data-look-picker/.test(read(path.join(PUB, 'home.html'))));

// ------------------------------------------------------------------- C
function stripComments(t) { return t.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' ')); }
function rootTokens(t) {
  const out = new Set();
  const re = /:root\{([\s\S]*?)\n\}/g; let m;
  const s = stripComments(t);
  while ((m = re.exec(s))) (m[1].match(/--[a-z0-9-]+(?=\s*:)/g) || []).forEach((k) => out.add(k));
  return out;
}
const base = new Set();
['home.css', 'hub.css', 'door.css'].forEach((f) => rootTokens(read(path.join(PUB, f))).forEach((k) => base.add(k)));
const blocks = {};
stripComments(LOOKS_CSS).replace(/:root\[data-([a-z]+)="([a-z]+)"\]\{([^}]*)\}/g, (m, kind, val, body) => {
  blocks[kind + '=' + val] = (body.match(/--[a-z0-9-]+(?=\s*:)/g) || []);
  return m;
});
const names = Object.keys(blocks);
yes('C looks.css has blocks', names.length > 0);
names.forEach((n) => {
  const bad = blocks[n].filter((k) => !base.has(k));
  yes('C ' + n + ' only sets tokens a base :root declares' + (bad.length ? ' (unknown: ' + bad.join(' ') + ')' : ''), bad.length === 0);
  const [kind, val] = n.split('=');
  yes('C ' + n + ' is an option looks.js offers, and not its default',
    !!OPTIONS[kind] && OPTIONS[kind].some((o) => o[0] === val) && OPTIONS[kind][0][0] !== val);
});
Object.keys(OPTIONS).forEach((kind) => OPTIONS[kind].slice(1).forEach((o) => {
  yes('C looks.js offers ' + kind + '=' + o[0] + ' and looks.css styles it', !!blocks[kind + '=' + o[0]]);
}));
yes('C a light palette keeps the hero over the painting on the Night tokens',
  /:root\[data-palette="parchment"\] #landing > \.hero\{[^}]*--page:#E4E7DA/.test(LOOKS_CSS));
const palettes = names.filter((n) => n.startsWith('palette='));
const colourBase = [...base].filter((k) => !/^--(w-|serif|sans|carve|mono|blurple)/.test(k));
palettes.forEach((n) => {
  const missing = colourBase.filter((k) => blocks[n].indexOf(k) < 0);
  yes('C ' + n + ' sets every colour token' + (missing.length ? ' (missing: ' + missing.join(' ') + ')' : ''), missing.length === 0);
});

// ------------------------------------------------------------------- D
['home.css', 'hub.css', 'door.css'].forEach((f) => {
  const raw = read(path.join(PUB, f));
  const lines = raw.split('\n');
  const clean = stripComments(raw.replace(/:root\{[\s\S]*?\n\}/g, (m) => m.replace(/[^\n]/g, ' '))).split('\n');
  const stray = [];
  clean.forEach((l, i) => {
    if (/look: fixed/.test(lines[i])) return;
    if (/#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(/.test(l)) stray.push((i + 1) + ': ' + lines[i].trim().slice(0, 90));
  });
  yes('D ' + f + ' has no colour outside :root that ignores the look' + (stray.length ? '\n      ' + stray.join('\n      ') : ''), stray.length === 0);
});

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
