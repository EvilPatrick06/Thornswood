'use strict';
/*
  test-2870-form-id-shape.js

      node tests\test-2870-form-id-shape.js

  Issue #2870. A deleted character's form id was kept two ways: the release
  list and the merchant ledger kept the local hex of a change form's formDesc
  ("a01" as 2561), the embassy rolls, dungeon chests and ship manifests the
  runtime form id (0xff000a01). From #2870 there is one shape, the runtime
  form id, 0xff000000 | local (game\form-id.js). This holds:

    F  formIdOf and isFormId, and every copy of them the same as the original
       (game\form-id.js); the PowerShell twin in scripts\ops\Release-List.ps1
       gives the same number for the same formDesc
    O  every reader refuses the old shape: the gamemode's release helper (a
       log line, nothing let go), the merchant purses (a version 1 ledger),
       Release-List.ps1 and scripts\vps\Server-Log.js (Delete-Person.ps1's
       refusal is in tests\test-2351-delete-person.ps1)
    C  scripts\ops\Convert-FormIdShape.js on stand-in servers: what it turns,
       what it keeps, the backup and its sums, done marks cleared for the
       parts that compare actors, a second run changing nothing, and every
       stop (pending trade, collision, a record it cannot read) changing
       nothing and taking no backup
    V  scripts\ops\Verify-FormIdShape.js counts before and after, and fails
       on an old shape left or a record lost

  Nothing leaves this machine. The scratch folder goes at the end.
*/
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const cp = require('child_process');
const crypto = require('crypto');

const REPO = path.join(__dirname, '..');
const FORM = require(path.join(REPO, 'game', 'form-id.js'));
const CONVERT = path.join(REPO, 'scripts', 'ops', 'Convert-FormIdShape.js');
const VERIFY = path.join(REPO, 'scripts', 'ops', 'Verify-FormIdShape.js');
const C = require(CONVERT);
const V = require(VERIFY);
const COMMISSION = require(path.join(REPO, 'game', 'merchant-commission-state.js'));
const read = (p) => fs.readFileSync(p, 'utf8').split(String.fromCharCode(13)).join('');
const gm = read(path.join(REPO, 'game', 'gamemode.js'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-2870-'));
function put(p, v) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, typeof v === 'string' ? v : JSON.stringify(v));
}
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const ledgerSum = (version, entries) => sha(JSON.stringify([version, entries]));

const A1 = 0xff000a01, A2 = 0xff000a02;   // 4278192641, 4278192642
const P1 = 5001, P2 = 5002;

try {
  // ---------------------------------------------------------------- F --
  const table = [
    ['1e', 0xff00001e], ['a01', A1], ['A01', A1], ['1', 0xff000001], ['ffffff', 0xffffffff], ['00a01', A1],
    ['0', 0], ['000000', 0], ['1000000', 0], ['ff000a01', 0], ['a01:Skyrim.esm', 0], ['', 0], [' a01', 0],
    ['a01 ', 0], ['-1', 0], ['0x1', 0], ['g1', 0], [null, 0], [undefined, 0], [2561, 0], [{}, 0]
  ];
  yes('F1 formDesc "1e" is the runtime form id 0xff00001e, as measured on a server (#2870)', FORM.formIdOf('1e') === 4278190110);
  const wrong = table.filter((r) => FORM.formIdOf(r[0]) !== r[1]).map((r) => JSON.stringify(r[0]));
  yes('F1 formIdOf gives the runtime form id of a local hex, 0 for anything else' + (wrong.length ? ' (' + wrong.join(', ') + ')' : ''), !wrong.length);
  const ids = [[0xff000000, false], [0xff000001, true], [A1, true], [0xffffffff, true], [0x100000000, false],
    [2561, false], [0, false], [-A1, false], [A1 + 0.5, false], [String(A1), false], [null, false]];
  const wrongIds = ids.filter((r) => FORM.isFormId(r[0]) !== r[1]).map((r) => String(r[0]));
  yes('F1 isFormId takes 0xff000001 to 0xffffffff, a whole number, and nothing else' + (wrongIds.length ? ' (' + wrongIds.join(', ') + ')' : ''), !wrongIds.length);

  // Every copy, line for line once its indent is taken off.
  const body = (text, name) => {
    const out = [];
    let at = 0;
    for (;;) {
      const a = text.indexOf('function ' + name + '(', at);
      if (a < 0) return out;
      const lines = text.slice(a).split('\n');
      const end = lines.findIndex((l) => l.trim() === '}');
      out.push(lines.slice(0, end + 1).map((l) => l.replace(/^\s+/, '')).join('\n'));
      at = a + 1;
    }
  };
  const original = read(path.join(REPO, 'game', 'form-id.js'));
  const want = { formIdOf: body(original, 'formIdOf')[0], isFormId: body(original, 'isFormId')[0] };
  yes('F2 game\\form-id.js has the original of each', !!want.formIdOf && !!want.isFormId && body(original, 'formIdOf').length === 1);
  const copies = [
    ['game/gamemode.js', 3, 3],                      // the release helper, the purses, the bundled commission state
    ['game/merchant-commission-state.js', 1, 1],
    ['scripts/vps/Delete-Person.ps1', 1, 1],
    ['scripts/vps/Server-Log.js', 0, 1],
    ['scripts/ops/Convert-FormIdShape.js', 1, 1],
    ['scripts/ops/Verify-FormIdShape.js', 1, 1]
  ];
  for (const [file, nf, ni] of copies) {
    const text = read(path.join(REPO, file));
    const f = body(text, 'formIdOf'), i = body(text, 'isFormId');
    yes('F2 ' + file + ' holds ' + nf + ' formIdOf and ' + ni + ' isFormId, each the same as game\\form-id.js',
        f.length === nf && i.length === ni && f.every((s) => s === want.formIdOf) && i.every((s) => s === want.isFormId));
  }

  // The PowerShell twin, on the same table.
  const strings = table.filter((r) => typeof r[0] === 'string');
  const ps1 = path.join(REPO, 'scripts', 'ops', 'Release-List.ps1');
  const q = (s) => "'" + String(s).split("'").join("''") + "'";
  function pwsh(script) {
    const r = cp.spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' });
    return { ok: !r.error && r.status === 0, out: (r.stdout || '').split(/\r?\n/).filter(Boolean), err: (r.error && r.error.message) || r.stderr || '' };
  }
  const dot = '. ' + q(ps1) + '; . ([scriptblock]::Create($ThornswoodReleaseList)); ';
  const twin = pwsh(dot + 'foreach ($d in @(' + strings.map((r) => q(r[0])).join(',') + ')) { [string](ConvertFrom-ThornswoodFormDesc $d) }; ' +
    '[string](ConvertFrom-ThornswoodFormDesc $null); [string](ConvertFrom-ThornswoodFormDesc 2561)');
  const twinWant = strings.map((r) => String(r[1])).concat(['0', '0']);
  yes('F3 ConvertFrom-ThornswoodFormDesc (Release-List.ps1) gives what formIdOf gives, formDesc by formDesc' + (twin.ok ? '' : ' (' + twin.err.trim() + ')'),
      twin.ok && JSON.stringify(twin.out) === JSON.stringify(twinWant));
  yes('F3 and the commission owner of a runtime character is its runtime form id; a placed form keeps its local id and plugin',
      COMMISSION.owner({ desc: 'a01', profileId: P1 }) === JSON.stringify([A1, '', P1]) &&
      COMMISSION.owner({ desc: 'a03:Skyrim.esm', profileId: 78 }) === JSON.stringify([0xa03, 'skyrim.esm', 78]) &&
      COMMISSION.ownerString(JSON.stringify([A1, '', P1])) && !COMMISSION.ownerString(JSON.stringify([2561, '', P1])));

  // ---------------------------------------------------------------- O --
  // The gamemode's release helper on an old shape list: nothing let go, said.
  const rs = '// ==== thornswood release of deleted characters ====', re = '// ==== end thornswood release of deleted characters ====';
  const release = gm.slice(gm.indexOf(rs), gm.indexOf(re) + re.length);
  function helper(list) {
    const dir = fs.mkdtempSync(path.join(scratch, 'helper-'));
    put(path.join(dir, 'server-settings.json'), { privDir: 'private' });
    put(path.join(dir, 'private', 'deleted-characters.json'), list);
    const logged = [];
    const box = { require: require, console: console, log: (s) => logged.push(String(s)) };
    box.globalThis = box;
    vm.createContext(box);
    const was = process.cwd();
    process.chdir(dir);
    let seen = null;
    try {
      vm.runInContext(release, box, { filename: 'gamemode.js (release)' });
      box.__thornswoodRelease('property', (who) => { seen = who; return { saved: true, counts: {} }; });
    } finally { process.chdir(was); }
    return { seen: seen, logged: logged, after: fs.readFileSync(path.join(dir, 'private', 'deleted-characters.json'), 'utf8') };
  }
  const oldList = JSON.stringify({ profiles: [P1], actors: [2561] });
  const h1 = helper(oldList);
  yes('O1 the release helper lets nothing go from a list of local ids, the old shape, and leaves it as it is',
      h1.seen === null && h1.after === oldList);
  yes('O1   and says so, naming the converter', h1.logged.some((l) => /holds form ids in the old shape \(#2870; scripts\\ops\\Convert-FormIdShape\.js converts it\), so nothing was let go and it is left as it is/.test(l)));
  const h2 = helper(JSON.stringify({ profiles: [P1], actors: [A1] }));
  yes('O1 a list of runtime form ids is read, and who.actor matches the runtime form id and never the local id',
      !!h2.seen && h2.seen.actor(A1) && !h2.seen.actor(2561) && h2.seen.actor(FORM.formIdOf('a01')));

  // The purses refuse a version 1 merchant ledger.
  const ps = gm.indexOf('// NPC MERCHANT PURSES BEGIN'), pe = gm.indexOf('// NPC MERCHANT PURSES END');
  const pctx = { Map: Map, Number: Number, JSON: JSON };
  vm.createContext(pctx);
  vm.runInContext(gm.slice(ps, pe), pctx);
  const papi = { makeProperty() { }, getIdFromDesc: (d) => (d === '1:Skyrim.esm' ? 1 : 0), get: () => undefined, set: () => { },
    getNpcAIState: () => ({ isHuman: false, profileId: 0, isDead: false }) };
  const pdata = { keep: [['1:Skyrim.esm', 'a:Skyrim.esm', null, null, null, null, 'trader']] };
  const purses = (version) => {
    const doc = { version: version, entries: { '1:Skyrim.esm': null } };
    try { pctx.createNpcMerchantPurses(papi, pdata, { namespace: 'v' + version, load: () => JSON.parse(JSON.stringify(doc)), save: () => true }); return ''; }
    catch (e) { return String(e && e.message); }
  };
  yes('O2 the merchant purses refuse a version 1 ledger, naming the converter',
      purses(1) === 'Saved merchant ledger is version 1, from before #2870; run scripts\\ops\\Convert-FormIdShape.js with the server stopped');
  yes('O2   and load a version 2 one', purses(2) === '');

  // Release-List.ps1 will not merge into an old shape list, and writes runtime form ids.
  const rl = path.join(scratch, 'release-list');
  put(path.join(rl, 'server-settings.json'), { privDir: 'private' });
  const rlFile = path.join(rl, 'private', 'deleted-characters.json');
  put(rlFile, oldList);
  put(path.join(rl, 'cf', 'a.json'), { formDesc: 'a01', profileId: P1 });
  put(path.join(rl, 'cf', 'b.json'), { formDesc: 'a02:Skyrim.esm', profileId: P2 });
  const rlRun = pwsh(dot + '$c = Get-ThornswoodCharacterIds @(' + q(path.join(rl, 'cf', 'a.json')) + ',' + q(path.join(rl, 'cf', 'b.json')) + '); ' +
    "'IDS ' + (@($c.ids) -join ','); foreach ($n in $c.notes) { $n }; " +
    'Write-ThornswoodReleaseList -Root ' + q(rl) + ' -Actors $c.ids');
  const rlSaid = rlRun.out.join('\n');
  yes('O3 Release-List.ps1 reads a character\'s runtime form id off its change form' + (rlRun.ok ? '' : ' (' + rlRun.err.trim() + ')'),
      rlRun.ok && rlRun.out.indexOf('IDS ' + A1) >= 0);
  yes('O3   and a formDesc with a plugin is no character of the list, said', /RELEASENOTE\|.*b\.json has a formDesc that is not a runtime form/.test(rlSaid));
  yes('O3   and it writes nothing into a list in the old shape, said, naming the converter',
      fs.readFileSync(rlFile, 'utf8') === oldList &&
      /RELEASEBAD\|.*holds form ids in the old shape \(#2870\), so no list was written and it is left as it is; scripts\\ops\\Convert-FormIdShape\.js converts it/.test(rlSaid));
  put(rlFile, JSON.stringify({ profiles: [P1], actors: [A2] }));
  const rlRun2 = pwsh(dot + 'Write-ThornswoodReleaseList -Root ' + q(rl) + ' -Actors @(' + A1 + ')');
  const merged = JSON.parse(fs.readFileSync(rlFile, 'utf8'));
  yes('O3   and merges runtime form ids into a list of them', rlRun2.ok && JSON.stringify(merged.actors) === JSON.stringify([A1, A2]));

  // Server-Log.js removes nothing for a list in the old shape.
  const sl = path.join(scratch, 'server-log');
  put(path.join(sl, 'server-settings.json'), { privDir: 'private' });
  put(path.join(sl, 'world', 'changeForms', 'a01.json'), { formDesc: 'a01', profileId: P1 });
  put(path.join(sl, 'private', 'deleted-characters.json'), oldList);
  put(path.join(sl, 'exit.js'), 'process.exit(0);');
  const slRun = cp.spawnSync(process.execPath, [path.join(REPO, 'scripts', 'vps', 'Server-Log.js'), '--log', path.join(sl, 'server.log'), 'exit.js'], { cwd: sl, encoding: 'utf8' });
  const slLog = fs.existsSync(path.join(sl, 'server.log')) ? fs.readFileSync(path.join(sl, 'server.log'), 'utf8') : '';
  yes('O4 Server-Log.js removes nothing for a list of local ids and leaves it as it is, said',
      slRun.status === 0 && fs.existsSync(path.join(sl, 'world', 'changeForms', 'a01.json')) &&
      fs.readFileSync(path.join(sl, 'private', 'deleted-characters.json'), 'utf8') === oldList &&
      /is not a list of deleted characters, so nothing was removed and it is left as it is/.test(slLog));

  // ---------------------------------------------------------------- C --
  const O1 = JSON.stringify([2561, '', P1]), O2 = JSON.stringify([2562, '', P2]), OP = JSON.stringify([0xa03, 'skyrim.esm', 78]);
  const N1 = JSON.stringify([A1, '', P1]), N2 = JSON.stringify([A2, '', P2]);
  const job = (owner, j) => JSON.stringify([owner, j]);
  function entriesV1() {
    return {
      '9:Skyrim.esm': {
        purse: 250, stock: [],
        supply: { [JSON.stringify(['a01', P1, 'iron ore'])]: 2, 'wheat': 1 },
        commissions: {
          serial: 3,
          held: { [job(O1, 'q-1')]: { owner: O1, gold: 5 }, [job(OP, 'q-3')]: { owner: OP, gold: 7 } },
          cool: { [job(O2, 'q-2')]: 100 }
        }
      },
      '8:Skyrim.esm': null
    };
  }
  const ledgerText = (entries, version, sum) => JSON.stringify({ version: version || 1, entries: entries,
    sha256: sum !== undefined ? sum : ledgerSum(version || 1, entries) });
  const LIST = '{\n  "profiles": [\n    5001\n  ],\n  "actors": [\n    2561,\n    4278192642\n  ],\n  "done": {\n    "saves": 1,\n    "farms": 2,\n    "embassy": 3,\n    "merchants": 4\n  }\n}\n';
  const EMBASSY = JSON.stringify({ embassy: [{ actor: A2, profileId: P2 }], remnant: [] });
  let serial = 0;
  function server(over) {
    const dir = path.join(scratch, 'server-' + (++serial));
    put(path.join(dir, 'server-settings.json'), { privDir: 'private' });
    const files = Object.assign({ 'merchant-ledger.json': ledgerText(entriesV1()), 'deleted-characters.json': LIST, 'embassy.json': EMBASSY }, over || {});
    for (const k of Object.keys(files)) if (files[k] !== null) put(path.join(dir, 'private', k), files[k]);
    return { dir: dir, priv: path.join(dir, 'private') };
  }
  const look = (priv) => fs.readdirSync(priv).sort().map((n) => {
    const p = path.join(priv, n);
    return n + (fs.statSync(p).isDirectory() ? '/' : ' ' + sha(fs.readFileSync(p)));
  }).join('\n');
  const NOW = Date.UTC(2026, 9, 22, 22, 0, 0);

  const s = server();
  const before = V.count(s.dir);
  yes('V1 the counts before: list actors 1 full and 1 local; the ledger version 1, its sha256 matching, 1 supply wait by formDesc, 1 by item, 2 local owners and 1 placed',
      before.list.actors.full === 1 && before.list.actors.local === 1 && before.embassy.actors.full === 1 &&
      before.merchants.version === 1 && before.merchants.sha256 === true && before.merchants.entries === 1 &&
      before.merchants.supply.desc === 1 && before.merchants.supply.itemOnly === 1 &&
      before.merchants.owners.local === 2 && before.merchants.owners.plugin === 1 && before.merchants.pending === 0);
  const was = { ledger: fs.readFileSync(path.join(s.priv, 'merchant-ledger.json')), list: fs.readFileSync(path.join(s.priv, 'deleted-characters.json')) };
  const r1 = C.convert(s.dir, { now: NOW });
  const ledger = JSON.parse(fs.readFileSync(path.join(s.priv, 'merchant-ledger.json'), 'utf8'));
  const e9 = ledger.entries['9:Skyrim.esm'];
  yes('C1 the ledger becomes version 2 with a matching sha256, compact as the purses write it',
      ledger.version === 2 && ledger.sha256 === ledgerSum(2, ledger.entries) &&
      fs.readFileSync(path.join(s.priv, 'merchant-ledger.json'), 'utf8') === JSON.stringify(ledger) && ledger.entries['8:Skyrim.esm'] === null);
  yes('C1   a supply wait keyed by formDesc is keyed by the runtime form id, one by item alone kept',
      JSON.stringify(Object.keys(e9.supply)) === JSON.stringify([JSON.stringify([A1, P1, 'iron ore']), 'wheat']) &&
      e9.supply[JSON.stringify([A1, P1, 'iron ore'])] === 2 && e9.supply.wheat === 1);
  yes('C1   a character\'s commission owner is its runtime form id, in the key and in the promise; a placed form\'s is kept',
      !!e9.commissions.held[job(N1, 'q-1')] && e9.commissions.held[job(N1, 'q-1')].owner === N1 && e9.commissions.held[job(N1, 'q-1')].gold === 5 &&
      !!e9.commissions.held[job(OP, 'q-3')] && e9.commissions.held[job(OP, 'q-3')].owner === OP &&
      e9.commissions.cool[job(N2, 'q-2')] === 100 && Object.keys(e9.commissions.cool).length === 1 && e9.commissions.serial === 3);
  yes('C1   and the converted owner is the one the commission state makes for that character now',
      !!e9.commissions.held[job(N1, 'q-1')] && COMMISSION.owner({ desc: 'a01', profileId: P1 }) === e9.commissions.held[job(N1, 'q-1')].owner);
  const listText = fs.readFileSync(path.join(s.priv, 'deleted-characters.json'), 'utf8');
  const list = JSON.parse(listText);
  yes('C2 the release list actors become runtime form ids, the file the shape it came in',
      JSON.stringify(list.actors) === JSON.stringify([A1, A2]) && JSON.stringify(list.profiles) === JSON.stringify([P1]) &&
      /^\{\n {2}"profiles"/.test(listText) && /\}\n$/.test(listText));
  yes('C2   parts that compare actors and were marked done are cleared to run again; the others keep their marks',
      JSON.stringify(list.done) === JSON.stringify({ saves: 1, farms: 2 }) &&
      JSON.stringify(r1.list.cleared) === JSON.stringify(['embassy', 'merchants']));
  yes('C2   and the gamemode\'s release helper reads the converted list for a part not done', !!helper(listText).seen);
  yes('C3 the report counts it: 1 supply key, 2 owner keys, 1 promise owner, 1 placed owner, 1 item-only wait, 1 list actor',
      r1.merchants.supplyKeys === 1 && r1.merchants.ownerKeys === 2 && r1.merchants.heldOwners === 1 && r1.merchants.placedOwners === 1 &&
      r1.merchants.itemOnlySupply === 1 && r1.list.changes === 1 && r1.changes === 1 + 1 + 2 + 1 + 1 &&
      JSON.stringify(r1.written) === JSON.stringify(['merchant-ledger.json', 'deleted-characters.json']) && r1.kept.embassy === 1);
  const bdir = path.join(s.priv, 'backup-2870-20261022T220000Z');
  const sums = fs.existsSync(path.join(bdir, 'SHA256SUMS')) ? fs.readFileSync(path.join(bdir, 'SHA256SUMS'), 'utf8') : '';
  yes('C4 the backup is taken first, in privDir\\backup-2870-<UTC time>, the files as they were',
      r1.backup === bdir && fs.readFileSync(path.join(bdir, 'merchant-ledger.json')).equals(was.ledger) &&
      fs.readFileSync(path.join(bdir, 'deleted-characters.json')).equals(was.list));
  yes('C4   with a SHA256SUMS that matches them',
      sums === sha(was.ledger) + '  merchant-ledger.json\n' + sha(was.list) + '  deleted-characters.json\n');
  const after = V.count(s.dir);
  yes('V2 the counts after: nothing lost, no old shape left, and compare passes',
      JSON.stringify(V.compare(before, after)) === '[]' && after.list.actors.full === 2 && after.merchants.version === 2 &&
      after.merchants.sha256 === true && after.merchants.supply.full === 1 && after.merchants.owners.full === 2 && after.merchants.owners.plugin === 1);
  const wasAll = look(s.priv);
  const r2 = C.convert(s.dir, { now: NOW + 60000 });
  yes('C5 a second run changes nothing and takes no backup', r2.changes === 0 && r2.backup === null && r2.written.length === 0 && look(s.priv) === wasAll);

  // Every stop: said, nothing changed, no backup taken.
  function stops(what, over, pattern) {
    const t = server(over);
    const lookBefore = look(t.priv);
    let why = null;
    try { C.convert(t.dir, { now: NOW }); } catch (e) { why = e instanceof C.Stop ? e.message : 'not a stop: ' + e.message; }
    yes('C6 it stops on ' + what + ', changing nothing and taking no backup' + (why && !pattern.test(why) ? ' (' + why + ')' : ''),
        why !== null && pattern.test(why) && look(t.priv) === lookBefore);
  }
  const withEntry = (fn) => { const e = entriesV1(); fn(e['9:Skyrim.esm']); return ledgerText(e); };
  stops('a pending trade', { 'merchant-ledger.json': withEntry((m) => { m.pending = { token: 1 }; }) }, /pending trade at 9:Skyrim\.esm/);
  stops('a release list that names one character both ways',
      { 'deleted-characters.json': JSON.stringify({ profiles: [P1], actors: [2561, A1] }) }, /twice once converted \(a collision\)/);
  stops('two supply waits that become one',
      { 'merchant-ledger.json': withEntry((m) => { m.supply[JSON.stringify(['A01', P1, 'iron ore'])] = 1; }) }, /two supply waits that become .* \(a collision\)/);
  stops('two commission records that become one',
      { 'merchant-ledger.json': withEntry((m) => { m.commissions.cool[job(O1, 'q-1')] = 5; }) }, /two commission records that become .* \(a collision\)/);
  stops('a supply wait keyed by a placed form', { 'merchant-ledger.json': withEntry((m) => { m.supply[JSON.stringify(['a01:Skyrim.esm', P1, 'x'])] = 1; }) },
      /supply wait not keyed by a runtime character/);
  stops('a supply wait it cannot read', { 'merchant-ledger.json': withEntry((m) => { m.supply['[1,2'] = 1; }) }, /supply wait that cannot be read/);
  stops('a commission owner it cannot read', { 'merchant-ledger.json': withEntry((m) => { m.commissions.cool[job('[x]', 'q-9')] = 1; }) }, /owner that cannot be read/);
  stops('a promise whose owner is not its key\'s', { 'merchant-ledger.json': withEntry((m) => { m.commissions.held[job(O1, 'q-1')].owner = O2; }) },
      /promise whose owner is not its key's/);
  stops('a ledger that does not match its sha256', { 'merchant-ledger.json': ledgerText(entriesV1(), 1, 'x') }, /does not match its sha256/);
  stops('a ledger version it does not know', { 'merchant-ledger.json': ledgerText(entriesV1(), 3) }, /version 3, which this does not know/);
  stops('a ledger that will not parse', { 'merchant-ledger.json': '{"version":1,' }, /merchant-ledger\.json cannot be parsed/);
  stops('a release list that will not parse', { 'deleted-characters.json': '{"profiles":[' }, /deleted-characters\.json cannot be parsed/);
  stops('a release list actor in neither shape', { 'deleted-characters.json': JSON.stringify({ profiles: [P1], actors: ['a01'] }) },
      /actor 0 \("a01"\) is neither a form id nor an old shape local id/);
  stops('an embassy roll that does not name a form id', { 'embassy.json': JSON.stringify({ embassy: [{ actor: 2561 }] }) }, /embassy\.json embassy row 0 does not name a form id/);
  stops('a dungeon chest that does not name a form id', { 'dungeon-rewards-ledger.json': JSON.stringify({ version: 1, entries: { c: { actor: 2561 } } }) },
      /dungeon-rewards-ledger\.json c does not name a form id/);
  stops('a ship register party that does not name a form id',
      { 'trade-cargo.json': JSON.stringify({ cargo: { holds: { h: { lines: { l: { by: { actor: 2561 } } }, outs: [] } } } }) }, /trade-cargo\.json hold h line l loader does not name a form id/);
  const t2 = server();
  fs.mkdirSync(path.join(t2.priv, 'backup-2870-20261022T220000Z'));
  let why2 = null;
  const look2 = look(t2.priv);
  try { C.convert(t2.dir, { now: NOW }); } catch (e) { why2 = e.message; }
  yes('C6 it stops when that backup folder is there already, changing nothing', /is there already; nothing was changed/.test(String(why2)) && look(t2.priv) === look2);

  // A server with only a version 2 ledger and no list has nothing to do.
  const t3 = server({ 'merchant-ledger.json': ledgerText({ '9:Skyrim.esm': null }, 2), 'deleted-characters.json': null });
  const r3 = C.convert(t3.dir, { now: NOW });
  yes('C7 a server already in the one shape is left as it is', r3.changes === 0 && r3.backup === null && r3.list === null);

  // The command line.
  const run = (file, args) => cp.spawnSync(process.execPath, [file].concat(args), { encoding: 'utf8', cwd: REPO });
  const u = run(CONVERT, ['--server', server().dir]);
  yes('C8 the converter will not run without --server-stopped (exit 2, usage)', u.status === 2 && /Usage: .*--server-stopped/.test(u.stderr));
  const cs = server({ 'merchant-ledger.json': withEntry((m) => { m.pending = 1; }) });
  const c1 = run(CONVERT, ['--server', cs.dir, '--server-stopped']);
  yes('C8 a stop exits 2 and prints why', c1.status === 2 && JSON.parse(c1.stdout).result === 'stopped' && /pending trade/.test(JSON.parse(c1.stdout).why));
  const cv = server();
  const vb = run(VERIFY, ['--server', cv.dir]);
  put(path.join(scratch, 'before.json'), vb.stdout);
  const c2 = run(CONVERT, ['--server', cv.dir, '--server-stopped']);
  const c3 = run(CONVERT, ['--server', cv.dir, '--server-stopped']);
  yes('C8 a run exits 0, "converted", then "nothing to change"',
      c2.status === 0 && JSON.parse(c2.stdout).result === 'converted' && c3.status === 0 && JSON.parse(c3.stdout).result === 'nothing to change');
  const va = run(VERIFY, ['--server', cv.dir, '--before', path.join(scratch, 'before.json')]);
  yes('V3 verify before exits 0, and after with --before passes, exit 0', vb.status === 0 && va.status === 0 && JSON.parse(va.stdout).result === 'passed');

  // Verify fails what it should.
  const vf = server();
  const bf = V.count(vf.dir);
  const why0 = V.compare(bf, V.count(vf.dir));
  yes('V4 compare fails an unconverted server: local actors, version 1, formDesc waits, local owners',
      why0.some((w) => /list still holds 1 old shape actors/.test(w)) && why0.some((w) => /version 1, not 2/.test(w)) &&
      why0.some((w) => /1 supply waits keyed by formDesc/.test(w)) && why0.some((w) => /2 old shape commission owners/.test(w)));
  C.convert(vf.dir, { now: NOW });
  const lost = JSON.parse(fs.readFileSync(path.join(vf.priv, 'merchant-ledger.json'), 'utf8'));
  delete lost.entries['9:Skyrim.esm'].supply.wheat;
  lost.sha256 = ledgerSum(2, lost.entries);
  put(path.join(vf.priv, 'merchant-ledger.json'), JSON.stringify(lost));
  put(path.join(vf.priv, 'embassy.json'), JSON.stringify({ embassy: [], remnant: [] }));
  const why1 = V.compare(bf, V.count(vf.dir));
  yes('V4 and a record lost: a supply wait, an embassy row',
      why1.some((w) => /held 2 supply waits and holds 1/.test(w)) && why1.some((w) => /embassy held 1 actors and holds 0/.test(w)));
  put(path.join(vf.priv, 'merchant-ledger.json'), '{');
  const vu = run(VERIFY, ['--server', vf.dir]);
  yes('V4 and a file it cannot read exits 1', vu.status === 1 && /cannot be parsed/.test(String(JSON.parse(vu.stdout).merchants.unreadable)));
} catch (e) {
  fail++;
  console.log('FAIL  the test itself threw: ' + ((e && e.stack) || e));
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}
console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);

