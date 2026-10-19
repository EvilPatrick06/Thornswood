// test-asset-provenance.js
//
//     node tests\test-asset-provenance.js
//
// Issue #2177: the asset provenance register, records\asset-provenance.json.
// Every picture, video, sound, font, mesh, texture, interface file and plugin
// in this repository is in it with where it came from, who made it, its
// licence or permission, the credit it asks for, who approved it, where it is
// published and its sha256, or it says plainly that one of those is not
// recorded and who can answer. This holds the register to the files, so a
// pull request that adds a picture, or changes one, goes red until somebody
// has looked at where it came from and written it down. That is the "release
// and content review detects missing provenance" of the issue's Done when.
//
// It checks:
//   1. the register reads, and every entry has every field, a known status,
//      and, where something is missing, an ask naming who can answer or the
//      issue that carries it;
//   2. every tracked file of an asset kind, and everything under game\ours,
//      is registered by its path, and every registered path is a file;
//   3. each registered file's sha256 is the one on record (text files as git
//      stores them, with LF line endings), so a changed file is looked at
//      again;
//   4. a derived file names a registered source, and a withheld one names the
//      record that keeps it out, which holds what the entry says: a set in
//      records\ui-gone.json, or a list in Ship-Rules.ps1 that holds every
//      path the entry names (the five files nothing uses, #2177); a file the
//      launcher makes from the person's own game names the Ship-Rules.ps1
//      list that keeps it out of every pack the same way (#2827);
//   5. no permission is copied in: no email address anywhere in it;
//   6. it stays operator only: nothing that builds a pack, the installer, the
//      launcher or the site names it, and it is not under site\public;
//   7. every font THIRD-PARTY.md names in the front build is registered;
//   8. the checks themselves catch a new picture, a changed one, a missing
//      ask and an email address, on planted copies.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const REGISTER = path.join(ROOT, 'records', 'asset-provenance.json');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// The kinds of file people see, hear or load into the game.
const ASSET = /\.(png|jpe?g|gif|webp|svg|ico|bmp|tga|dds|nif|mp3|mp4|webm|ogg|wav|flac|xwm|fuz|ttf|otf|woff2?|spritefont|swf|esp|esm|esl|bsa)$/i;
// Text kinds, hashed as git stores them: a Windows checkout adds a CR to
// every line, which changes the bytes on disk but not the file.
const TEXT = /\.(svg|txt|ini|json|xml)$/i;
const FIELDS = ['path', 'what', 'published', 'source', 'creator', 'licence', 'attribution', 'approved', 'evidence', 'status'];
const NEEDS_ASK = ['unconfirmed', 'agreed-not-written'];
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}/;

function hashOf(rel) {
  let b = fs.readFileSync(path.join(ROOT, rel));
  if (TEXT.test(rel)) b = Buffer.from(b.toString('latin1').split('\r\n').join('\n'), 'latin1');
  return crypto.createHash('sha256').update(b).digest('hex');
}

// Every file git tracks; the folders walked when git is not there to ask.
function tracked() {
  try {
    return execFileSync('git', ['-C', ROOT, 'ls-files'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
      .split(/\r?\n/).filter(Boolean);
  } catch (e) {
    const out = [];
    (function walk(rel) {
      for (const d of fs.readdirSync(path.join(ROOT, rel), { withFileTypes: true })) {
        const r = rel ? rel + '/' + d.name : d.name;
        if (d.isDirectory()) { if (!/^(\.git|node_modules|out|local|engine)$/.test(d.name)) walk(r); }
        else out.push(r);
      }
    })('');
    return out;
  }
}

// The quoted paths of one list in Ship-Rules.ps1, $<name> = @( ... ).
function shipList(text, name) {
  const m = new RegExp('^\\$' + name + ' = @\\(([\\s\\S]*?)^\\)', 'm').exec(text || '');
  return m ? (m[1].match(/'[^']+'/g) || []).map((q) => q.slice(1, -1)) : [];
}

// Each finding is one line saying what is wrong and what to do.
function audit(reg, files, hash, uiGone, shipRules) {
  const bad = [];
  if (!reg || reg.version !== 1) { bad.push('the register is not version 1'); return bad; }
  const statuses = Object.keys(reg.statuses || {});
  const assets = Array.isArray(reg.assets) ? reg.assets : [];
  const elsewhere = Array.isArray(reg.notInRepo) ? reg.notInRepo : [];
  const byPath = new Map();
  for (const a of assets) {
    if (byPath.has(a.path)) bad.push(a.path + ': registered twice');
    byPath.set(a.path, a);
  }
  for (const a of assets.concat(elsewhere)) {
    const name = a.path || '(an entry with no path)';
    for (const f of FIELDS) if (typeof a[f] !== 'string' || !a[f].trim()) bad.push(name + ': no ' + f);
    if (statuses.indexOf(a.status) < 0) bad.push(name + ': status "' + a.status + '" is not one the register defines');
    if (NEEDS_ASK.indexOf(a.status) >= 0 && !(typeof a.ask === 'string' && /^[^:]{2,}: \S/.test(a.ask))) bad.push(name + ': ' + a.status + ' with no ask naming who can answer ("Who: what")');
    if (a.status === 'no-licence-found' && !(Number.isInteger(a.issue) && a.issue > 0)) bad.push(name + ': no licence found, and no issue that carries it');
    if (a.status === 'withheld' || a.status === 'made-from-game') {
      const m = /^records\/ui-gone\.json#(\w+)$/.exec(a.record || '');
      const r = /^scripts\/release\/Ship-Rules\.ps1#(\w+)$/.exec(a.record || '');
      if (r) {
        const list = shipList(shipRules, r[1]);
        const paths = Array.isArray(a.paths) ? a.paths : [];
        const out = paths.filter((x) => list.indexOf(x) < 0);
        if (!list.length || !paths.length) bad.push(name + ': ' + a.status + ' by Ship-Rules.ps1 $' + r[1] + ', but that list or the entry\'s paths are empty');
        else if (out.length) bad.push(name + ': ' + a.status + ' by Ship-Rules.ps1 $' + r[1] + ', which does not hold ' + out.join(', '));
      } else if (a.status === 'made-from-game') {
        bad.push(name + ': made from the game, but names no Ship-Rules.ps1 list that keeps it out of packs');
      } else {
        const held = m && uiGone ? uiGone[m[1]] : null;
        const n = held ? (Array.isArray(held) ? held.length : Object.keys(held).length) : 0;
        if (!n) bad.push(name + ': withheld, but names no record that holds it out');
      }
    }
  }
  for (const a of assets) {
    if (!/^[0-9a-f]{64}$/.test(a.sha256 || '')) { bad.push(a.path + ': no sha256'); continue; }
    if (files.indexOf(a.path) < 0) { bad.push(a.path + ': registered, but no such file is tracked'); continue; }
    const h = hash(a.path);
    if (h !== a.sha256) bad.push(a.path + ': changed since it was registered (now ' + h + '). Look at where the new file came from, then write its entry and hash again');
    if (a.status === 'derived') {
      const src = byPath.get(a.from);
      if (!src) bad.push(a.path + ': derived from "' + a.from + '", which is not registered');
      else if (src.status === 'withheld') bad.push(a.path + ': derived from a withheld file');
    }
  }
  for (const f of files) {
    if (!(ASSET.test(f) || /^game\/ours\//.test(f))) continue;
    if (!byPath.has(f)) bad.push(f + ': not in records\\asset-provenance.json. Register where it came from, who made it, its licence or permission, credit, approval, where it is published and its sha256, or say which of those is not recorded and who can answer');
  }
  const text = JSON.stringify(reg);
  const mail = EMAIL.exec(text);
  if (mail) bad.push('an email address is in the register (' + mail[0] + '): a permission and who gave it stay out of the repository; say where it is kept instead');
  return bad;
}

// ---- 1 to 5: the register against the files -------------------------------------
let reg = null;
try { reg = JSON.parse(fs.readFileSync(REGISTER, 'utf8')); } catch (e) { console.log('  ' + e.message); }
yes('records\\asset-provenance.json reads as JSON', reg !== null);
let uiGone = null;
try { uiGone = JSON.parse(fs.readFileSync(path.join(ROOT, 'records', 'ui-gone.json'), 'utf8')); } catch (e) { }
let shipRules = '';
try { shipRules = fs.readFileSync(path.join(ROOT, 'scripts', 'release', 'Ship-Rules.ps1'), 'utf8'); } catch (e) { }
const files = tracked();
yes('the repository\'s files can be listed (' + files.length + ')', files.length > 100);
const found = audit(reg, files, hashOf, uiGone, shipRules);
for (const b of found) console.log('  ' + b);
yes('every asset is registered with every field, its sha256 matches, and nothing in it is a permission (' + found.length + ' finding(s))', found.length === 0);
if (reg) {
  const all = (reg.assets || []).concat(reg.notInRepo || []);
  const count = (s) => all.filter((a) => a.status === s).length;
  console.log('  ' + Object.keys(reg.statuses).map((s) => s + ' ' + count(s)).join(', '));
  yes('the register says what it is and that it is operator only', /Operator only/.test(reg.about || '') && /never written here/.test(reg.about || ''));
  yes('the 37 Daedric Online files are withheld by the record that deletes them', (reg.notInRepo || []).some((a) => a.status === 'withheld' && a.record === 'records/ui-gone.json#daedric') && uiGone && Object.keys(uiGone.daedric || {}).length === 37);
  yes('the five files nothing uses are withheld by the Ship-Rules.ps1 list every pack deletes (#2177)',
    (reg.notInRepo || []).filter((a) => a.status === 'withheld' && a.record === 'scripts/release/Ship-Rules.ps1#ShipPlatformUnused')
      .reduce((n, a) => n + (Array.isArray(a.paths) ? a.paths.length : 0), 0) === 5 &&
    shipList(shipRules, 'ShipPlatformUnused').length === 5);
  yes('the three files the launcher makes from the game are registered, held out by the Ship-Rules.ps1 list (#2827)',
    (reg.notInRepo || []).filter((a) => a.status === 'made-from-game' && a.record === 'scripts/release/Ship-Rules.ps1#ShipMadeFromGame')
      .reduce((n, a) => n + (Array.isArray(a.paths) ? a.paths.length : 0), 0) === 3 &&
    shipList(shipRules, 'ShipMadeFromGame').length === 3);
  yes('community uploads and the collection\'s mods are dispositioned', (reg.dispositions || []).length >= 2 && (reg.dispositions || []).some((d) => /gallery/i.test(d.what)) && (reg.dispositions || []).some((d) => /collection/i.test(d.what)));
}

// ---- 6: operator only --------------------------------------------------------------
const builders = ['scripts/release/Build-Launcher.ps1', 'scripts/release/Package-Thornswood.ps1', 'scripts/release/Publish-Update.ps1',
  'scripts/release/Ship-Rules.ps1', 'scripts/release/Go.ps1', 'scripts/deploy/Deploy-Docs.ps1', 'site/server.js'];
const naming = builders.filter((f) => { try { return /asset-provenance/.test(fs.readFileSync(path.join(ROOT, f), 'utf8')); } catch (e) { return false; } });
yes('nothing that builds a pack, the installer, the launcher or the site names it' + (naming.length ? ' (' + naming.join(', ') + ')' : ''), naming.length === 0);
yes('  and it is not under site\\public, which the site serves whole', !fs.existsSync(path.join(ROOT, 'site', 'public', 'asset-provenance.json')));

// ---- 7: THIRD-PARTY.md's front fonts are registered ---------------------------------
const notices = (() => { try { return fs.readFileSync(path.join(ROOT, 'THIRD-PARTY.md'), 'utf8'); } catch (e) { return ''; } })();
const fonts = Array.from(new Set((notices.match(/\b[0-9a-f]{20}\.ttf\b/g) || [])));
const regText = reg ? JSON.stringify(reg.notInRepo || []) : '';
const missing = fonts.filter((f) => regText.indexOf(f) < 0);
yes('every hashed front font THIRD-PARTY.md names is registered (' + fonts.length + (missing.length ? '; missing ' + missing.join(', ') : '') + ')', fonts.length >= 6 && missing.length === 0);
const sprites = Array.from(new Set((notices.match(/\b[A-Za-z-]+\.spritefont\b/g) || [])));
const missingSprites = sprites.filter((f) => regText.indexOf(f) < 0);
yes('every sprite font THIRD-PARTY.md names is registered (' + sprites.length + (missingSprites.length ? '; missing ' + missingSprites.join(', ') : '') + ')', sprites.length >= 5 && missingSprites.length === 0);

// ---- 8: the checks catch what they are for, on planted copies -----------------------
if (reg) {
  const copy = () => JSON.parse(JSON.stringify(reg));
  const some = (reg.assets || []).find((a) => a.status === 'unconfirmed');
  let r = audit(copy(), files.concat(['site/public/new-picture.png']), hashOf, uiGone, shipRules);
  yes('a new picture nobody registered is caught', r.some((b) => /^site\/public\/new-picture\.png: not in records/.test(b)));
  r = audit(copy(), files, (p) => (p === some.path ? '0'.repeat(64) : hashOf(p)), uiGone, shipRules);
  yes('a registered picture that changed is caught', r.some((b) => b.indexOf(some.path + ': changed since it was registered') === 0));
  const c = copy(); delete c.assets.find((a) => a.path === some.path).ask;
  r = audit(c, files, hashOf, uiGone, shipRules);
  yes('an unconfirmed entry with no ask is caught', r.some((b) => b.indexOf(some.path + ': unconfirmed with no ask') === 0));
  const d = copy(); d.assets[0].evidence = 'licence by email from someone@example.com';
  r = audit(d, files, hashOf, uiGone, shipRules);
  yes('an email address copied in is caught', r.some((b) => /an email address is in the register/.test(b)));
  const e = copy(); e.notInRepo.find((a) => a.status === 'withheld').record = 'records/ui-gone.json#nothing';
  r = audit(e, files, hashOf, uiGone, shipRules);
  yes('a withheld entry naming no real record is caught', r.some((b) => /withheld, but names no record/.test(b)));
  const f = copy(); f.notInRepo.find((a) => a.record === 'scripts/release/Ship-Rules.ps1#ShipPlatformUnused').paths.push('Data\\Platform\\Fonts\\Tavern.ttf');
  r = audit(f, files, hashOf, uiGone, shipRules);
  yes('a withheld entry naming a path its Ship-Rules list does not hold is caught', r.some((b) => /which does not hold Data\\Platform\\Fonts\\Tavern\.ttf/.test(b)));
  const g = copy(); g.notInRepo.find((a) => a.status === 'made-from-game').paths.push('Data\\Interface\\map.swf');
  r = audit(g, files, hashOf, uiGone, shipRules);
  yes('a file said to be made from the game that its Ship-Rules list does not hold is caught', r.some((b) => /made-from-game by Ship-Rules\.ps1 \$ShipMadeFromGame, which does not hold Data\\Interface\\map\.swf/.test(b)));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
