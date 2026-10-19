'use strict';
// test-2792-terms-game-files.js
//
//     node tests\test-2792-terms-game-files.js
//
// The terms page says exactly which of Bethesda's files, and which files
// built from Bethesda's, Thornswood hands on. Issue #2792.
//
// WHY THIS EXISTS. Until 19 October terms.md said "Thornswood ships no game
// files", while every pack and the installer carried Data\Interface\
// startmenu.swf, Skyrim's own interface file edited (#2177), and the notice
// board and drop box meshes, built from pieces of Skyrim's own (#2502). The
// page was written before those shipped, and nothing compared it with the
// pack list. Patrick picked on 19 Oct (#2792, option 1) to make the page
// exact. This holds it exact from now on:
//
//   1. every file Ship-Rules.ps1 $ShipOursFiles ships whose register entry
//      (records\asset-provenance.json) says Bethesda made it, or that it was
//      built from Bethesda's, is named on the terms page by its file name;
//   2. the number of the game's own files the page says it hands on ("one of
//      the game's own files") is the number of shipped entries whose source
//      is Skyrim's own file;
//   3. the page and the credits page carry the line Bethesda's terms for
//      mods ask for (Creation Kit licence 2.B);
//   4. the checks catch a new shipped Bethesda file the page does not name,
//      and a count that no longer matches, on planted copies.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

const ROOT = REPO_DIR;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function read(rel) {
  try { return fs.readFileSync(path.join(ROOT, rel), 'utf8').split('\r\n').join('\n'); }
  catch (e) { return null; }
}

// A Ship-Rules list, its comments taken out first: they hold apostrophes
// ("Daedric Online's") that would pair with the quotes around the paths.
function shipList(text, name) {
  const m = new RegExp('^\\$' + name + ' = @\\(([\\s\\S]*?)^\\)', 'm').exec(text || '');
  if (!m) return [];
  const body = m[1].split('\n').map((l) => l.replace(/#.*$/, '')).join('\n');
  return (body.match(/'[^']+'/g) || []).map((q) => q.slice(1, -1));
}

const NUMBERS = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
const NOTICE = 'THIS MOD IS NOT MADE, GUARANTEED OR SUPPORTED BY ZENIMAX OR ITS AFFILIATES.';
function flat(t) { return (t || '').replace(/\s+/g, ' '); }

// Each finding is one line saying what is wrong.
function audit(reg, ships, terms) {
  const bad = [];
  const shipped = (reg.assets || []).filter((a) => {
    const m = /^game\/ours\/(Data\/.+)$/.exec(a.path || '');
    return m && ships.indexOf(m[1].split('/').join('\\')) >= 0;
  });
  const bethesdas = shipped.filter((a) => /Bethesda/.test(a.creator || ''));
  for (const a of bethesdas) {
    const name = a.path.split('/').pop();
    if (flat(terms).indexOf(name) < 0) bad.push(a.path + ': ships and is Bethesda\'s or built from Bethesda\'s, and terms.md does not name ' + name);
  }
  const own = shipped.filter((a) => /^Skyrim's own /.test(a.source || ''));
  const said = /hands on (\w+) of the game's own files/.exec(flat(terms));
  if (!said) bad.push('terms.md does not say how many of the game\'s own files Thornswood hands on ("hands on N of the game\'s own files")');
  else if (NUMBERS.indexOf(said[1].toLowerCase()) !== own.length) {
    bad.push('terms.md says it hands on ' + said[1] + ' of the game\'s own files, and ' + own.length + ' ship: ' + own.map((a) => a.path).join(', '));
  }
  return { bad: bad, bethesdas: bethesdas, own: own };
}

const reg = JSON.parse(read('records/asset-provenance.json') || '{}');
const ships = shipList(read('scripts/release/Ship-Rules.ps1'), 'ShipOursFiles');
const terms = read('site/data/site/terms.md');
const credits = read('site/data/site/credits.md');
yes('the register, $ShipOursFiles, terms.md and credits.md read', reg.version === 1 && ships.length > 0 && terms !== null && credits !== null);

const r = audit(reg, ships, terms);
yes('the shipped files that are Bethesda\'s or built from Bethesda\'s are found in the register (' + r.bethesdas.map((a) => a.path.split('/').pop()).join(', ') + ')', r.bethesdas.length > 0);
yes('terms.md names every one of them, and says how many of the game\'s own files ship' + (r.bad.length ? ': ' + r.bad.join('; ') : ''), r.bad.length === 0);
yes('terms.md carries the notice line Bethesda\'s terms for mods ask for', flat(terms).indexOf(NOTICE) >= 0);
yes('and so does credits.md', flat(credits).indexOf(NOTICE) >= 0);

// ----------------------------------------------------- the checks bite --
function copy() { return JSON.parse(JSON.stringify(reg)); }
const planted = copy();
planted.assets.push({ path: 'game/ours/Data/Interface/map.swf', creator: 'Bethesda Game Studios', source: "Skyrim's own interface\\map.swf, edited" });
const p1 = audit(planted, ships.concat(['Data\\Interface\\map.swf']), terms);
yes('a new shipped Bethesda file the page does not name is caught', p1.bad.some((b) => b.indexOf('map.swf: ships') >= 0));
yes('and so is the count of the game\'s own files no longer matching', p1.bad.some((b) => /says it hands on one .* and 2 ship/.test(b)));
const p2 = audit(reg, ships.filter((s) => !/startmenu\.swf$/.test(s)), terms);
yes('a page that says one when none ships is caught', p2.bad.some((b) => /and 0 ship/.test(b)));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
