/*
  test-2923-own-plugins.js

  #2923. Thornswood's own plugins (every file in game/content) are made and
  shipped from this repository. Build-FoodTable.js and Build-RecipeTable.ps1
  read them from the game's Data folder, which holds whichever release last
  reached it (on One, a Content plugin from 12 Oct), so a content change could
  only be built by making a Data folder of links to the repository's copy.
  And nothing said which tables a content change makes stale: #2911 found
  them one red build at a time.

  H  the three helpers (scripts/dev/OwnPlugins.js, OwnPlugins.ps1,
     own_plugins.py) say the same thing: a file in game/content is read from
     there, any other plugin from the Data folder.
  F  Build-FoodTable.js, given a Data folder holding a stale content plugin,
     builds from the repository's.
  R  no builder that reads a load order joins the Data folder with a plugin
     name itself.
  C  scripts/mods/content-tables.json, the list
     scripts/mods/Rebuild-ContentTables.ps1 runs: every builder that reads a
     load order is in it or left out with a reason, no step reads a table a
     later step writes, and the script lists every step.
  N  the harnesses that hold a table to the plugin's bytes name the script.
  L  #2976. The load order is read in one place: the three helpers say the
     same of a plugins.txt holding switched off lines (the masters, then each
     '*' line, once), and no builder reads plugins.txt's lines itself.
     tests/test-1712-builders-skip-off.js runs the builders on such a list.

  Nothing outside a temporary folder is written.
*/
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const DEV = path.join(ROOT, 'scripts', 'dev');
const OWN_DIR = path.join(ROOT, 'game', 'content');

let pass = 0, fail = 0;
function yes(w, c) { if (c) { pass++; console.log('PASS  ' + w); } else { fail++; console.log('FAIL  ' + w); } }
function read(rel) { return fs.readFileSync(path.join(ROOT, rel), 'utf8').split(String.fromCharCode(13)).join(''); }
function run(exes, args, opts) {
  for (const exe of exes) {
    const p = spawnSync(exe, args, Object.assign({ encoding: 'utf8', maxBuffer: 1 << 26 }, opts || {}));
    if (!p.error) { return p; }
  }
  return null;
}

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'tw-2923-'));
const DATA = path.join(TMP, 'Data');
fs.mkdirSync(DATA);
const OWN = fs.readdirSync(OWN_DIR).filter((n) => fs.statSync(path.join(OWN_DIR, n)).isFile());

// ---------------------------------------------------------------- H
yes('H0 game/content holds Thornswood-Content.esp and Thornswood-Last.esp',
    ['Thornswood-Content.esp', 'Thornswood-Last.esp'].every((n) => OWN.indexOf(n) >= 0));
const js = require(path.join(DEV, 'OwnPlugins.js'));
yes('H1 OwnPlugins.js reads every file in game/content from there (' + OWN.length + ')',
    OWN.every((n) => path.resolve(js.pluginPath(DATA, n)) === path.resolve(OWN_DIR, n)));
yes('H2 and any other plugin from the Data folder',
    path.resolve(js.pluginPath(DATA, 'Skyrim.esm')) === path.resolve(DATA, 'Skyrim.esm'));

const want = OWN.map((n) => path.resolve(OWN_DIR, n)).concat([path.resolve(DATA, 'Skyrim.esm')]);
const names = OWN.concat(['Skyrim.esm']);
const py = run(['python', 'py', 'python3'], ['-c',
  'import sys; sys.path.insert(0, sys.argv[1]); import own_plugins\n' +
  'for n in sys.argv[3:]: print(own_plugins.plugin_path(sys.argv[2], n))', DEV, DATA].concat(names));
if (!py) {
  console.log('SKIP  H3: no python here');
} else {
  const got = py.stdout.trim().split(/\r?\n/).map((l) => path.resolve(l.trim()));
  yes('H3 own_plugins.py says the same for each', py.status === 0 && JSON.stringify(got) === JSON.stringify(want));
  if (py.status !== 0) { console.log(py.stderr); }
}
const asks = path.join(TMP, 'asks.ps1');
fs.writeFileSync(asks, 'param([string]$Dev, [string]$Data, [string]$Names)\n' +
  '. (Join-Path $Dev \'OwnPlugins.ps1\')\n' +
  'foreach ($n in ($Names -split \',\')) { Get-PluginPath $Data $n }\n');
const ps = run(['pwsh', 'powershell'], ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', asks, '-Dev', DEV, '-Data', DATA,
  '-Names', names.join(',')]);
if (!ps) {
  console.log('SKIP  H4: no PowerShell here');
} else {
  const got = ps.stdout.trim().split(/\r?\n/).map((l) => path.resolve(l.trim()));
  yes('H4 OwnPlugins.ps1 says the same for each', ps.status === 0 && JSON.stringify(got) === JSON.stringify(want));
  if (ps.status !== 0) { console.log(ps.stderr); }
}

// ---------------------------------------------------------------- F
// A plugin in the shape Build-FoodTable.js reads: TES4 with its masters,
// then one ALCH group (the same layout as tests/test-food-table.js).
function zs(s) { return Buffer.concat([Buffer.from(s, 'latin1'), Buffer.alloc(1)]); }
function sub(tag, data) { const h = Buffer.alloc(6); h.write(tag, 0, 'ascii'); h.writeUInt16LE(data.length, 4); return Buffer.concat([h, data]); }
function record(type, formId, flags, data) {
  const h = Buffer.alloc(24);
  h.write(type, 0, 'ascii'); h.writeUInt32LE(data.length, 4); h.writeUInt32LE(flags >>> 0, 8); h.writeUInt32LE(formId >>> 0, 12);
  return Buffer.concat([h, data]);
}
function group(label, recs) {
  const body = Buffer.concat(recs);
  const h = Buffer.alloc(24);
  h.write('GRUP', 0, 'ascii'); h.writeUInt32LE(24 + body.length, 4); h.write(label, 8, 'ascii');
  return Buffer.concat([h, body]);
}
function alch(formId, edid, name) {
  const enit = Buffer.alloc(20);
  enit.writeUInt32LE(5, 0); enit.writeUInt32LE(2, 4);
  return record('ALCH', formId, 0, Buffer.concat([sub('EDID', zs(edid)), sub('FULL', zs(name)), sub('ENIT', enit)]));
}
function plugin(masters, recs) {
  const hedr = Buffer.alloc(12);
  hedr.writeFloatLE(1.71, 0); hedr.writeUInt32LE(recs.length, 4); hedr.writeUInt32LE(0x800, 8);
  const parts = [sub('HEDR', hedr)];
  masters.forEach((m) => { parts.push(sub('MAST', zs(m))); parts.push(sub('DATA', Buffer.alloc(8))); });
  return Buffer.concat([record('TES4', 0, 0, Buffer.concat(parts)), group('ALCH', recs)]);
}
const REPO = path.join(TMP, 'repo');
const GAME = path.join(TMP, 'Game', 'Data');
for (const d of ['scripts/dev', 'game/data', 'game/content', 'Profile/Default']) { fs.mkdirSync(path.join(REPO, d), { recursive: true }); }
fs.mkdirSync(GAME, { recursive: true });
for (const f of ['Build-FoodTable.js', 'OwnPlugins.js']) { fs.copyFileSync(path.join(DEV, f), path.join(REPO, 'scripts', 'dev', f)); }
fs.writeFileSync(path.join(REPO, 'game', 'gamemode.js'), 'const FOODS = {"items":{}};\n');
fs.writeFileSync(path.join(GAME, 'Skyrim.esm'), plugin([], [alch(0x00064b3d, 'FoodSweetroll', 'Sweet Roll')]));
for (const m of ['Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm']) { fs.writeFileSync(path.join(GAME, m), plugin(['Skyrim.esm'], [])); }
// The game folder's copy is an older release; the repository's has the tea.
fs.writeFileSync(path.join(GAME, 'Thornswood-Content.esp'), plugin(['Skyrim.esm'], [alch(0x01018004, 'ThornswoodOldStew', 'Old Stew')]));
fs.writeFileSync(path.join(REPO, 'game', 'content', 'Thornswood-Content.esp'), plugin(['Skyrim.esm'], [alch(0x01018001, 'ThornswoodTeaLavender', 'Lavender Tea')]));
const list = path.join(TMP, 'plugins.txt');
fs.writeFileSync(list, '*Thornswood-Content.esp\r\n');
const food = spawnSync(process.execPath, [path.join(REPO, 'scripts', 'dev', 'Build-FoodTable.js'), '--data', GAME, '--plugins', list], { encoding: 'utf8' });
let items = {};
try { items = JSON.parse(fs.readFileSync(path.join(REPO, 'game', 'data', 'food.json'), 'utf8')).items; } catch (e) { items = {}; }
yes('F1 Build-FoodTable.js runs on a Data folder holding a stale content plugin (exit ' + food.status + ')', food.status === 0);
yes('F2 and the table is the repository\'s plugin: the tea is in it',
    !!items['18001:Thornswood-Content.esp'] && items['18001:Thornswood-Content.esp'].name === 'Lavender Tea');
yes('F3 and the game folder\'s older copy is not', !items['18004:Thornswood-Content.esp']);
if (food.status !== 0) { console.log(food.stdout + food.stderr); }

// ---------------------------------------------------------------- R
const builders = [];
for (const dir of ['scripts/dev', 'scripts/mods']) {
  for (const n of fs.readdirSync(path.join(ROOT, dir))) {
    if (/^(Build|Write|Audit)-.*\.(js|ps1|py)$/.test(n)) { builders.push(dir + '/' + n); }
  }
}
// A builder that reads a load order names a plugin list or the load order a
// table was built against.
const LOAD_ORDER = /plugins\.txt|PluginsTxt|PluginList|last-plugin\.json|npc-population\.json'?\)?\[?['"]loadOrder/;
// Or reads npc-population.json into a name and walks its loadOrder later, as
// Build-MerchantRetrievalSources.py does; the line above missed that one, so
// a content change left its table stale with no step to rebuild it (#2993).
const POPULATION_WALK = (src) => /npc-population\.json/.test(src) && /\[['"]loadOrder['"]\]|\.loadOrder\b/.test(src);
const readers = builders.filter((b) => LOAD_ORDER.test(read(b)) || POPULATION_WALK(read(b)));
const RAW = [
  /path\.join\(\s*(DATA|data|dataDir)\s*,\s*(pl|p|file|name|n|plugin)\s*\)/,
  /Join-Path\s+\$Data\s+\$(pl|p|plugin)\b/,
  /os\.path\.join\(\s*(args\.|a\.)?(data|data_dir)\s*,\s*(n|name|plugin|pl|row\[['"]name['"]\])\s*\)/
];
// Build-MerchantRoleTables.py writes the same rule out against its own ROOT,
// which its harness moves: own = ROOT / 'game/content' / name.
const SAME_RULE = { 'scripts/dev/Build-MerchantRoleTables.py': /own = ROOT \/ 'game\/content' \/ name\n\s+path = own if own\.is_file\(\) else data \/ name/ };
const raw = [];
for (const b of readers) {
  const src = read(b);
  if (SAME_RULE[b]) { if (!SAME_RULE[b].test(src)) { raw.push(b + ' (its own copy of the rule is gone)'); } continue; }
  src.split('\n').forEach((l, i) => { if (RAW.some((r) => r.test(l))) { raw.push(b + ':' + (i + 1) + ' ' + l.trim()); } });
}
yes('R1 ' + readers.length + ' builders read a load order, and none joins the Data folder with a plugin name itself' +
    (raw.length ? ' (' + raw.slice(0, 4).join('; ') + ')' : ''), readers.length >= 25 && raw.length === 0);
yes('R2 Build-FoodTable.js and Build-RecipeTable.ps1 read through the helper',
    /pluginPath\(DATA, file\)/.test(read('scripts/dev/Build-FoodTable.js')) &&
    (read('scripts/dev/Build-RecipeTable.ps1').match(/Get-PluginPath \$Data \$p/g) || []).length === 4);

// ---------------------------------------------------------------- C
const chain = JSON.parse(read('scripts/mods/content-tables.json'));
const steps = chain.steps || [];
const tools = steps.map((s) => s.tool);
const out = Object.keys(chain.notInChain || {});
yes('C1 every step is a builder in this checkout, once (' + steps.length + ')',
    steps.length > 0 && tools.every((t) => fs.existsSync(path.join(ROOT, t))) && new Set(tools).size === tools.length);
const missingFromChain = readers.filter((b) => tools.indexOf(b) < 0 && out.indexOf(b) < 0);
yes('C2 every builder that reads a load order is a step or is left out with its reason' +
    (missingFromChain.length ? ' (not: ' + missingFromChain.join(', ') + ')' : ''),
    missingFromChain.length === 0 && out.every((t) => fs.existsSync(path.join(ROOT, t)) && String(chain.notInChain[t]).length > 40));
const helperUsers = builders.filter((b) => /OwnPlugins\.(js|ps1)|import own_plugins/.test(read(b)));
yes('C3 and so is every builder that uses the helper (' + helperUsers.length + ')',
    helperUsers.every((b) => tools.indexOf(b) >= 0 || out.indexOf(b) >= 0));
const late = [];
steps.forEach((s, i) => {
  for (const r of s.reads || []) {
    steps.slice(i + 1).forEach((t) => { if ((t.writes || []).indexOf(r) >= 0) { late.push(s.tool + ' reads ' + r + ', which ' + t.tool + ' writes after it'); } });
  }
  for (const r of s.readsBack || []) {
    if (!steps.slice(i + 1).some((t) => (t.writes || []).indexOf(r) >= 0)) { late.push(s.tool + ' says a later step writes ' + r + ' back, and none does'); }
  }
});
yes('C4 no step reads a table a later step writes' + (late.length ? ' (' + late.slice(0, 3).join('; ') + ')' : ''), late.length === 0);
const unnamed = [];
for (const s of steps) {
  const src = read(s.tool);
  for (const f of (s.reads || []).concat(s.readsBack || [], s.writes || [])) {
    if (src.indexOf(path.basename(f)) < 0) { unnamed.push(s.tool + ' ' + f); }
  }
}
yes('C5 each step\'s own source names every table it is said to read and write' + (unnamed.length ? ' (not: ' + unnamed.slice(0, 4).join('; ') + ')' : ''),
    unnamed.length === 0);
const flags = [];
for (const s of steps) {
  const src = read(s.tool);
  for (const k of ['data', 'plugins']) {
    if (s[k] && src.indexOf(s[k].replace(/^-(?!-)/, '$').replace(/^--/, '')) < 0) { flags.push(s.tool + ' ' + s[k]); }
  }
}
yes('C6 and takes the Data folder and plugin list by the names the list gives' + (flags.length ? ' (not: ' + flags.join('; ') + ')' : ''),
    flags.length === 0);
const script = read('scripts/mods/Rebuild-ContentTables.ps1');
yes('C7 Rebuild-ContentTables.ps1 runs content-tables.json and writes the register\'s hashes',
    /content-tables\.json/.test(script) && /asset-provenance\.json/.test(script));
const shell = run(['pwsh', 'powershell'], ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
  path.join(ROOT, 'scripts', 'mods', 'Rebuild-ContentTables.ps1'), '-List', '-Data', DATA]);
if (!shell) {
  console.log('SKIP  C8: no PowerShell here');
} else {
  const said = shell.stdout;
  yes('C8 and -List names every step in order, with the Data folder, and runs nothing (exit ' + shell.status + ')',
      shell.status === 0 && tools.every((t, i) => said.indexOf((i + 1) + '. ' + t) >= 0) && /Nothing was run\./.test(said));
  if (shell.status !== 0) { console.log(said + shell.stderr); }
}

// ---------------------------------------------------------------- N
const naming = ['tests/test-2468-last-plugin.js', 'tests/test-2551-building-holds.js', 'tests/test-516-woodworking-benches.js',
  'tests/test-asset-provenance.js', 'docs/systems/station-placement.md', 'Developer-Guide.md'];
const silent = naming.filter((f) => read(f).indexOf('Rebuild-ContentTables.ps1') < 0);
yes('N1 the harnesses that hold a table to the plugin\'s bytes, and the docs, name the script' + (silent.length ? ' (not: ' + silent.join(', ') + ')' : ''),
    silent.length === 0);

// ---------------------------------------------------------------- L
// The shape of One's Default\plugins.txt on 20 Oct, cut down: ElysiumEstateSSE.esp
// switched off with its file gone, the live ElysiumEstate.esp switched on, and
// a byte order mark, a comment, a master written into the list, a name twice in
// two cases and a switched off line for a plugin that is also switched on.
const LIST = path.join(TMP, 'plugins-2976.txt');
fs.writeFileSync(LIST, '\ufeff# This file is used by Skyrim to keep track of your downloaded content.\r\n' +
  '*Skyrim.esm\r\n*Unofficial Skyrim Special Edition Patch.esp\r\nCBBE.esp\r\n*ElysiumEstate.esp\r\n' +
  '\r\nElysiumEstateSSE.esp\r\n*elysiumestate.esp\r\n  *Thornswood-Content.esp  \r\nThornswood-Content.esp\r\nCBBE.esp\r\n');
const WANT_ON = js.MASTERS.concat(['Unofficial Skyrim Special Edition Patch.esp', 'ElysiumEstate.esp', 'Thornswood-Content.esp']);
const WANT_OFF = ['CBBE.esp', 'ElysiumEstateSSE.esp'];
yes('L1 OwnPlugins.js reads the five masters and then each switched on line, once',
    JSON.stringify(js.loadOrder(LIST)) === JSON.stringify(WANT_ON));
yes('L2 and names the switched off lines, none of them loaded', JSON.stringify(js.switchedOff(LIST)) === JSON.stringify(WANT_OFF));
const pyL = run(['python', 'py', 'python3'], ['-c',
  'import json, sys; sys.path.insert(0, sys.argv[1]); import own_plugins\n' +
  'on, off = own_plugins.read_plugins_txt(sys.argv[2])\n' +
  'print(json.dumps([own_plugins.MASTERS, own_plugins.load_order(sys.argv[2]), on, off, own_plugins.switched_off(sys.argv[2])]))', DEV, LIST]);
if (!pyL) {
  console.log('SKIP  L3: no python here');
} else {
  let got = null;
  try { got = JSON.parse(pyL.stdout); } catch (e) { got = null; }
  yes('L3 own_plugins.py says the same', !!got && JSON.stringify(got) ===
      JSON.stringify([js.MASTERS, WANT_ON, WANT_ON, WANT_OFF, WANT_OFF]));
  if (!got) { console.log(pyL.stdout + pyL.stderr); }
}
const asksL = path.join(TMP, 'asks-2976.ps1');
fs.writeFileSync(asksL, 'param([string]$Dev, [string]$List)\n' +
  '. (Join-Path $Dev \'OwnPlugins.ps1\')\n' +
  'ConvertTo-Json -Compress -InputObject @(@(Get-LoadOrder $List), @(Get-SwitchedOff $List))\n');
const psL = run(['pwsh', 'powershell'], ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', asksL, '-Dev', DEV, '-List', LIST]);
if (!psL) {
  console.log('SKIP  L4: no PowerShell here');
} else {
  let got = null;
  try { got = JSON.parse(psL.stdout); } catch (e) { got = null; }
  yes('L4 OwnPlugins.ps1 says the same', !!got && JSON.stringify(got) === JSON.stringify([WANT_ON, WANT_OFF]));
  if (!got || JSON.stringify(got[0]) !== JSON.stringify(WANT_ON)) { console.log(psL.stdout + psL.stderr); }
}
// A builder that parses plugins.txt itself tests a line for its leading '*'.
const STAR = [/startswith\(\s*['"]\*['"]\s*\)/i, /\[0\]\s*[!=]==?\s*['"]\*['"]/, /charAt\(0\)\s*[!=]==?\s*['"]\*['"]/];
const parsers = [];
for (const dir of ['scripts/dev', 'scripts/mods']) {
  for (const n of fs.readdirSync(path.join(ROOT, dir))) {
    if (!/^(Build|Write|Audit|Measure)-.*\.(js|ps1|py)$/.test(n)) { continue; }
    read(dir + '/' + n).split('\n').forEach((l, i) => { if (STAR.some((r) => r.test(l))) { parsers.push(dir + '/' + n + ':' + (i + 1)); } });
  }
}
yes('L5 no builder reads plugins.txt\'s lines itself; each takes its load order from the helper' +
    (parsers.length ? ' (' + parsers.slice(0, 6).join(', ') + ')' : ''), parsers.length === 0);

fs.rmSync(TMP, { recursive: true, force: true });
console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
