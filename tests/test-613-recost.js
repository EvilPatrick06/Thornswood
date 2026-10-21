'use strict';
/*
  test-613-recost.js

  #613. Patrick, 21 October 2026, on the report page, A: re-cost only the smith
  recipes whose materials are priced nothing like what they make, to the
  typical ratio, in a generated plugin built on One and shipped as a release.

  scripts/dev/Build-Recost.py writes game/data/recost.json from
  game/data/recipes.json, and scripts/mods/Build-LastPlugin.py carries each
  row in Thornswood-Last.esp as the winning record with only its input counts
  changed. Without the game this holds:

    T  the table is what the rule gives (Build-Recost.py --check), and every
       row in it is a smith's at the forge or the Skyforge that was outside
       the band, comes out nearer the target, asks at least one of each
       input, and keeps the same inputs in the same order
    L  the builder, run over two small plugins written here: a re-costed
       recipe comes out as the winner with the new counts, its form ids in
       the new plugin's numbering, everything else the same, in a COBJ group;
       a winner whose inputs are not the ones the table measured stops the
       build

  The rebuild against the real load order is test-2468-last-plugin.js, on a
  machine with the game.
*/
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const ROOT = path.join(__dirname, '..');
const TABLE = path.join(ROOT, 'game', 'data', 'recost.json');
const RECIPES = path.join(ROOT, 'game', 'data', 'recipes.json');
const TOOL = path.join(ROOT, 'scripts', 'dev', 'Build-Recost.py');
const LAST = path.join(ROOT, 'scripts', 'mods', 'Build-LastPlugin.py');

let pass = 0, fail = 0;
function yes(w, c) { if (c) { pass++; console.log('PASS  ' + w); } else { fail++; console.log('FAIL  ' + w); } }
function done() { console.log('\n' + pass + ' passed, ' + fail + ' failed'); process.exit(fail ? 1 : 0); }
function python(args, input) {
  for (const exe of ['python', 'py', 'python3']) {
    const p = spawnSync(exe, args, { encoding: 'utf8', input: input, maxBuffer: 1 << 26,
                                     env: Object.assign({}, process.env, { PYTHONDONTWRITEBYTECODE: '1' }) });
    if (!p.error) { return p; }
  }
  return null;
}

// ------------------------------------------------------------------ the table
const check = python([TOOL, '--check']);
yes('T1 game/data/recost.json is what the rule gives (' + (check ? check.stdout.trim().split('\n').pop() : 'no python') + ')',
    !!check && check.status === 0);

const table = JSON.parse(fs.readFileSync(TABLE, 'utf8'));
const recipes = JSON.parse(fs.readFileSync(RECIPES, 'utf8')).recipes;
const rule = table.rule;
yes('T2 the rule is the one decided: smith rows at the forge and the Skyforge, outside 0.5 to 4, to the median',
    rule.owner === 'Smith' && rule.low === 0.5 && rule.high === 4 &&
    rule.benches.join() === 'CraftingSmithingForge,CraftingSmithingSkyforge' && rule.target > 1 && rule.target < 2.5);
yes('T3 its counts are its rows (' + table.counts.recosted + ' re-costed, ' + table.counts.unreachable +
    ' no count can fix, of ' + table.counts.priced + ' priced)',
    table.recipes.length === table.counts.recosted && table.unreachable.length === table.counts.unreachable &&
    table.counts.recosted > 0 && table.counts.priced > table.counts.recosted);
const bad = [];
for (const r of table.recipes) {
  const row = recipes[r.recipe];
  const outside = r.ratioWas < rule.low || r.ratioWas >= rule.high;
  const nearer = Math.abs(Math.log(r.ratioNow / rule.target)) < Math.abs(Math.log(r.ratioWas / rule.target));
  const atLeastOne = r.inputs.every((i) => Number.isInteger(i.to) && i.to >= 1);
  const changed = r.inputs.some((i) => i.to !== i.count);
  // The record's own inputs, as measured, or as this table has made them once the plugin carries it.
  const items = row ? row.inputItems.map((i) => i.item).join() : '';
  const sameItems = items === r.inputs.map((i) => i.item).join();
  const counts = row ? row.inputItems.map((i) => i.count).join() : '';
  const known = counts === r.inputs.map((i) => i.count).join() || counts === r.inputs.map((i) => i.to).join();
  const ok = row && row.owner === 'Smith' && rule.benches.indexOf(row.benchName) >= 0 && row.fires !== false &&
             outside && nearer && atLeastOne && changed && sameItems && known;
  if (!ok) { bad.push(r.recipe + ' ' + r.name); }
}
yes('T4 every re-costed row is a smith\'s, was outside the band, comes out nearer the target, asks at least one ' +
    'of each of the same inputs in the same order' + (bad.length ? ' (not: ' + bad.slice(0, 4).join(', ') + ')' : ''),
    bad.length === 0);
yes('T5 a row no count can fix is listed with why and carries no change',
    table.unreachable.every((r) => r.why && r.inputs.every((i) => i.to === i.count)));

// ------------------------------------------------------------------ the builder
const RIG = String.raw`
import importlib.util, json, os, struct, sys, tempfile
spec = importlib.util.spec_from_file_location('last', sys.argv[1])
L = importlib.util.module_from_spec(spec); spec.loader.exec_module(L)

def sub(t, d): return t + struct.pack('<H', len(d)) + d
def rec(t, fid, subs): body = b''.join(subs); return struct.pack('<4sIIIIHH', t, len(body), 0, fid, 0, 44, 0) + body
def grup(label, body): return struct.pack('<4sI4siHHI', b'GRUP', 24 + len(body), label, 0, 0, 0, 0) + body
def plugin(masters, groups):
    head = [sub(b'HEDR', struct.pack('<fiI', 1.71, 0, 0x800))]
    for m in masters: head += [sub(b'MAST', m.encode() + b'\x00'), sub(b'DATA', struct.pack('<Q', 0))]
    return rec(b'TES4', 0, head) + b''.join(groups)

d = tempfile.mkdtemp()
open(os.path.join(d, 'Skyrim.esm'), 'wb').write(plugin([], []))
cobj = rec(b'COBJ', 0x01000800, [sub(b'EDID', b'RecipeTest\x00'), sub(b'COCT', struct.pack('<I', 2)),
          sub(b'CNTO', struct.pack('<Ii', 0x0005ACE4, 2)), sub(b'CNTO', struct.pack('<Ii', 0x01000900, 3)),
          sub(b'CNAM', struct.pack('<I', 0x01000901)), sub(b'BNAM', struct.pack('<I', 0x00088105)),
          sub(b'NAM1', struct.pack('<H', 1))])
open(os.path.join(d, 'Mod.esp'), 'wb').write(plugin(['Skyrim.esm'], [grup(b'COBJ', cobj)]))
plugins = [L.Plugin(os.path.join(d, 'Skyrim.esm'), 'Skyrim.esm', 0), L.Plugin(os.path.join(d, 'Mod.esp'), 'Mod.esp', 1)]
win = L.winners(plugins, {b'COBJ'})
row = {'recipe': '800:Mod.esp', 'editorId': 'RecipeTest',
       'inputs': [{'item': '5ace4:Skyrim.esm', 'count': 2, 'to': 5}, {'item': '900:Mod.esp', 'count': 3, 'to': 7}]}
out = {}
got = L.recost_entries({'recipes': [row]}, plugins, win)
rn = L.Renumber()
e = got[0][0]
L.copy_record(plugins[e.pi], e, rn, None, 'test')
rn.masters = ['skyrim.esm', 'mod.esp']
pairs = L.recount(L.copy_record(plugins[e.pi], e, rn, None, 'test'), row)
made = {'achr': [], 'refr': [], 'cell': {}, 'wrld': {}, 'qust': [], 'lctn': [],
        'cobj': [(rn.one(plugins[e.pi], e.fid, 'test'), 0, L.pack_subrecords(pairs), e)]}
built = L.write_plugin(made, ['Skyrim.esm', 'Mod.esp'], plugins, rn)
back = L.read_plugin(built, 'Thornswood-Last.esp', 2)
entries = back.walk({b'COBJ'})
subs = L.subrecords(back.data(entries[0])) if entries else []
out['groups'] = [built[p:p + 4].decode() for p in [24 + struct.unpack_from('<I', built, 4)[0]]] + \
                [built[24 + struct.unpack_from('<I', built, 4)[0] + 8:24 + struct.unpack_from('<I', built, 4)[0] + 12].decode()]
out['records'] = len(entries)
out['fid'] = entries[0].fid if entries else None
out['cnto'] = [list(struct.unpack('<Ii', b)) for t, b in subs if t == b'CNTO']
out['rest'] = [t.decode() for t, b in subs]
out['same'] = [b.hex() for t, b in subs if t != b'CNTO'] == [b.hex() for t, b in L.subrecords(plugins[1].data(e)) if t != b'CNTO']
out['masters'] = back.masters
out['light'] = bool(back.hflags & L.LIGHT)
row2 = dict(row, inputs=[dict(row['inputs'][0], count=9), row['inputs'][1]])
try:
    L.recost_entries({'recipes': [row2]}, plugins, win); out['refused'] = ''
except SystemExit as x:
    out['refused'] = str(x)
try:
    L.recost_entries({'recipes': [dict(row, recipe='801:Mod.esp')]}, plugins, win); out['missing'] = ''
except SystemExit as x:
    out['missing'] = str(x)
print(json.dumps(out))
`;
const run = python(['-', LAST], RIG);
let r = null;
try { r = JSON.parse(run.stdout.trim().split('\n').pop()); } catch (e) { r = null; }
yes('L0 the builder runs over two small plugins written here' + (r ? '' : ' (' + (run ? run.stderr.slice(-400) : 'no python') + ')'), !!r);
if (!r) { done(); }
yes('L1 the re-costed recipe is one override in a COBJ group of a light plugin', r.records === 1 &&
    r.groups[0] === 'GRUP' && r.groups[1] === 'COBJ' && r.light);
yes('L2 it asks the table\'s counts, each input in the new plugin\'s numbering (' + JSON.stringify(r.cnto) + ')',
    JSON.stringify(r.cnto) === JSON.stringify([[0x0005ACE4, 5], [0x01000900, 7]]) && r.fid === 0x01000800 &&
    r.masters.join() === 'Skyrim.esm,Mod.esp');
yes('L3 and everything else is the winning record\'s own: editor id, input count, output, bench, how many it makes',
    r.same && r.rest.join() === 'EDID,COCT,CNTO,CNTO,CNAM,BNAM,NAM1');
yes('L4 a winner whose inputs are not the ones the table measured stops the build (' + r.refused.slice(0, 60) + ')',
    /is not the recipe recost\.json measured/.test(r.refused));
yes('L5 so does a recipe no plugin has', /no plugin has it/.test(r.missing));

// ------------------------------------------------------------------ wiring
const tool = fs.readFileSync(LAST, 'utf8');
yes('W1 the builder reads game/data/recost.json, puts COBJ first among its groups, and checks the re-costed counts win',
    /RECOST = os\.path\.join\(ROOT, 'game', 'data', 'recost\.json'\)/.test(tool) &&
    /GROUP_ORDER = \[b'COBJ', b'CELL'/.test(tool) && /does not ask the re-costed counts/.test(tool));

done();
