// test-table-install.js
//
// A table builder run on a load order that has not changed says the table is
// current and exits 0; one with nowhere to put its table still fails.
//
// WHY THIS EXISTS. Issue #1138. Build-WarmthTable.js, Build-WaterTable.js and
// Build-WeatherTable.js install their compact table into game/gamemode.js by
// replacing one line, and decided whether that worked by asking whether the
// file changed. When the table they built was the one already there, nothing
// changed, so they printed "FAIL could not find anywhere in gamemode.js to put
// the table" and exited 1: an up to date table read as a broken run. Seen for
// all three against a copy of origin/main where all three were current.
// Build-FoodTable.js and Build-RaceTable.js had been fixed the same way before.
//
// HOW. Each builder's own install() is lifted out of the file and run over a
// stand-in gamemode.js, with a table of two rows, in four states:
//   1. the anchor line it goes after and no table: it is put in after the anchor
//   2. run again over what 1 wrote: nothing written, it says so, exit not 1
//   3. a table that differs: the line is replaced, nothing else moves
//   4. neither the table nor the anchor: FAIL, exit 1, nothing written
//
// Read only. Nothing is written anywhere; the stand-in fs keeps the file.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* function install() { ... } out of a builder, by its braces. */
function liftInstall(src) {
  const at = src.indexOf('\nfunction install() {');
  if (at < 0) { return null; }
  const open = src.indexOf('{', at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') { depth++; }
    else if (src[i] === '}') { depth--; if (depth === 0) { return src.slice(at + 1, i + 1); } }
  }
  return null;
}

/*
  Each builder: the const it installs, the line it goes after when there is
  none yet, and the table variables its install() reads, two rows of each.
*/
const BUILDERS = [
  { file: 'Build-WarmthTable.js', name: 'WARMTH', anchor: 'ITEMS',
    vars: { items: { '1:Skyrim.esm': { m: 'fur', c: 4 }, '2:Skyrim.esm': { m: 'cloth', c: 2 } } } },
  { file: 'Build-WaterTable.js', name: 'WATERS', anchor: 'ITEMS',
    vars: { where: { 'a:Skyrim.esm': 'w1', 'b:Skyrim.esm': 'w2' },
            waters: { w1: { c: 'cold' }, w2: { c: 'warm' } } } },
  { file: 'Build-WeatherTable.js', name: 'WEATHER', anchor: 'ITEMS',
    vars: { items: { '3:Skyrim.esm': { w: 10, k: 'snow' }, '4:Skyrim.esm': { w: 2, k: 'clear' } },
            maxWind: 10, midWind: 5 } },
  { file: 'Build-FoodTable.js', name: 'FOODS', anchor: 'WARMTH',
    vars: { items: { '5:Skyrim.esm': 'ale', '6:Skyrim.esm': 'bread' } } },
  { file: 'Build-RaceTable.js', name: 'RACES', anchor: 'FOODS',
    vars: { rows: { '7:Skyrim.esm': { e: 'NordRace', p: true }, '8:Skyrim.esm': { n: 'Riekling', p: false } } } }
];

/* One run of a lifted install() over `gm`, the text of a stand-in gamemode.js. */
function run(fn, vars, gm) {
  const out = { wrote: null, said: [], failed: [] };
  const fakeFs = {
    readFileSync: function () { return gm; },
    writeFileSync: function (p, s) { out.wrote = String(s); }
  };
  const proc = { exitCode: undefined };
  const fakeConsole = {
    log: function (m) { out.said.push(String(m)); },
    error: function (m) { out.failed.push(String(m)); }
  };
  const failFn = function (m) { out.failed.push('FAIL  ' + m); proc.exitCode = 1; };
  const names = Object.keys(vars);
  const make = Function.apply(null, ['fs', 'path', '__dirname', 'console', 'process', 'fail']
    .concat(names).concat([fn + '\nreturn install;']));
  const install = make.apply(null, [fakeFs, path, path.join(REPO_DIR, 'scripts', 'dev'), fakeConsole, proc, failFn]
    .concat(names.map(function (n) { return vars[n]; })));
  install();
  out.exitCode = proc.exitCode;
  return out;
}

for (const b of BUILDERS) {
  const src = fs.readFileSync(path.join(REPO_DIR, 'scripts', 'dev', b.file), 'utf8').split('\r').join('');
  const fn = liftInstall(src);
  yes(b.file + ': install() is there to lift', !!fn);
  if (!fn) { continue; }

  const head = '// the gamemode\nconst ' + b.anchor + ' = {"items":{}};\nconst AFTER = 1;\n';

  // 1. the anchor and no table yet
  const r1 = run(fn, b.vars, head);
  const lineRx = new RegExp('^const ' + b.name + ' = .*;$', 'm');
  yes(b.file + ': with no table yet it puts one in, after const ' + b.anchor,
      r1.wrote !== null && lineRx.test(r1.wrote) &&
      r1.wrote.indexOf('const ' + b.anchor + ' = ') < r1.wrote.indexOf('const ' + b.name + ' = ') &&
      r1.exitCode !== 1);
  if (r1.wrote === null) { continue; }

  // 2. the same table again
  const r2 = run(fn, b.vars, r1.wrote);
  yes(b.file + ': run again on the same tables, nothing is written and it does not fail',
      r2.wrote === null && r2.exitCode !== 1 && r2.failed.length === 0);
  yes(b.file + ': and it says the table is already there (' + (r2.said[0] || '') + ')',
      r2.said.some(function (s) { return /already/.test(s); }));

  // 3. a table that differs
  const stale = r1.wrote.replace(lineRx, 'const ' + b.name + ' = {"items":{"old":1}};');
  const r3 = run(fn, b.vars, stale);
  yes(b.file + ': a table that differs is replaced, and the lines around it stay',
      r3.wrote === r1.wrote && r3.exitCode !== 1);

  // 4. nowhere to put it
  const r4 = run(fn, b.vars, '// a gamemode with neither line\nconst AFTER = 1;\n');
  yes(b.file + ': with neither its table nor const ' + b.anchor + ' it fails and writes nothing',
      r4.wrote === null && r4.exitCode === 1 &&
      r4.failed.some(function (s) { return /could not find anywhere in gamemode\.js to put the table/.test(s); }));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
