// test-502-kill-bounty.js
//
// #502. Patrick, 11 October: "there should be no bounties at all added when
// killing NPCs". Nothing Thornswood wrote adds a bounty; Skyrim's own crime
// system does, in each person's game, through the crime faction of whoever
// was killed or struck. The front plugin sets the ignore murder and ignore
// assault flags on every faction scripts\dev\Build-CrimeTable.py found in
// which a kill or a blow costs gold, once a game is loaded.
//
// This holds together:
//   - the plugin's KILL_CRIME_FACTIONS block and game\data\crime-factions.json,
//     which the script writes from the same reading of the load order;
//   - every hold's crime faction the gamemode knows (DATA.holds) is on it,
//     Raven Rock's too, and CrimeFactionReach, the one with its own amounts;
//   - the plugin's noKillBounty, run against a stand-in Skyrim Platform: both
//     flags on every faction, read back, and the log line naming any faction
//     that is missing or did not take them;
//   - it runs on loadGame, through guard;
//   - nothing in game\ adds a bounty itself.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const CR = String.fromCharCode(13);
const front = fs.readFileSync(path.join(REPO_DIR, 'game', 'plugins', 'thornswood-front.js'), 'utf8').split(CR).join('');
const gm = fs.readFileSync(path.join(REPO_DIR, 'game', 'gamemode.js'), 'utf8').split(CR).join('');
let table = null;
try { table = JSON.parse(fs.readFileSync(path.join(REPO_DIR, 'game', 'data', 'crime-factions.json'), 'utf8')); } catch (e) { table = null; }
yes('game/data/crime-factions.json is in the repo, written by the script',
    !!table && table.builtBy === 'scripts/dev/Build-CrimeTable.py' && !!table.factions);
yes('scripts/dev/Build-CrimeTable.py is in the repo',
    fs.existsSync(path.join(REPO_DIR, 'scripts', 'dev', 'Build-CrimeTable.py')));

const START = '  // ==== KILL_CRIME_FACTIONS, generated ====';
const END = "  sp.on('loadGame', guard('no kill bounty', noKillBounty));";
const a = front.indexOf(START);
const b = front.indexOf(END);
yes('the front plugin carries the generated block and the function after it', a >= 0 && b > a);
yes('they are in the plugin once', front.indexOf(START, a + 1) < 0 && front.indexOf(END, b + 1) < 0);
const body = (a >= 0 && b > a) ? front.slice(a, b) : '';

let rows = null;
try { rows = new Function(body.slice(0, body.indexOf('  function noKillBounty(')) + '\nreturn KILL_CRIME_FACTIONS;')(); } catch (e) { rows = null; }
yes('the block is a list of [form id, plugin, editor id]', Array.isArray(rows) && rows.length > 0 &&
    rows.every(function (r) { return Array.isArray(r) && r.length === 3 && Number.isInteger(r[0]) &&
                                     typeof r[1] === 'string' && typeof r[2] === 'string'; }));
const descs = (rows || []).map(function (r) { return r[0].toString(16) + ':' + r[1]; });
const fromJson = table ? Object.keys(table.factions).sort() : [];
yes('the block and the json list the same factions (' + descs.length + ')',
    descs.slice().sort().join(',') === fromJson.join(','));
yes('and give each the same editor id', (rows || []).every(function (r) {
  const j = table && table.factions[r[0].toString(16) + ':' + r[1]];
  return !!j && j.edid === r[2];
}));
yes('every one of them costs gold for a kill or a blow, by the json',
    fromJson.every(function (k) { const f = table.factions[k]; return f.murder > 0 || f.assault > 0; }));

// Every hold's crime faction the gamemode knows, by DATA.holds.
const dataLine = gm.split('\n').filter(function (l) { return l.indexOf('const DATA = ') === 0; })[0] || '';
let DATA = null;
try { DATA = JSON.parse(dataLine.slice('const DATA = '.length).replace(/;\s*$/, '')); } catch (e) { DATA = null; }
const holdFactions = [];
if (DATA && DATA.holds) {
  for (const h in DATA.holds) {
    const c = DATA.holds[h].crimeFaction;
    if (c) { holdFactions.push(parseInt(c, 16).toString(16) + ':Skyrim.esm'); }
  }
}
yes('the gamemode names nine hold crime factions', holdFactions.length === 9);
const missingHolds = holdFactions.filter(function (d) { return descs.indexOf(d) < 0; });
yes('every hold crime faction is on the list' + (missingHolds.length ? ' (not: ' + missingHolds.join(', ') + ')' : ''),
    missingHolds.length === 0);
yes('Raven Rock\'s is on it', descs.indexOf('18279:Dragonborn.esm') >= 0);
yes('the Reach is on it, the faction with its own amounts that a game setting would not reach',
    descs.indexOf('2816c:Skyrim.esm') >= 0 && table && table.factions['2816c:Skyrim.esm'] &&
    table.factions['2816c:Skyrim.esm'].useDefaults === false);

/* The plugin's function, run against a stand-in Skyrim Platform. */
function run(opts) {
  const flags = {};
  const logged = [];
  const sp = {
    Game: {
      getFormFromFile: function (id, file) {
        const k = id.toString(16) + ':' + file;
        if (opts.absent && opts.absent.indexOf(k) >= 0) { return null; }
        return { k: k };
      }
    },
    Faction: {
      from: function (form) {
        if (!form) { return null; }
        const k = form.k;
        return {
          setFactionFlag: function (f) {
            if (opts.throwOn === k) { throw new Error('no SKSE'); }
            if (opts.sticky === k) { return; }
            flags[k] = (flags[k] || 0) | f;
          },
          isFactionFlagSet: function (f) { return ((flags[k] || 0) & f) !== 0; }
        };
      }
    }
  };
  const say = function (t) { logged.push(t); };
  const fn = new Function('sp', 'say', body + '\nreturn noKillBounty;')(sp, say);
  fn();
  return { flags: flags, logged: logged };
}

let r = null;
try { r = run({}); } catch (e) { console.log('      threw: ' + e); r = null; }
yes('noKillBounty runs', !!r);
if (r) {
  const both = descs.filter(function (d) { return ((r.flags[d] || 0) & 0x180) === 0x180; });
  yes('every faction on the list now ignores murder and assault (' + both.length + ' of ' + descs.length + ')',
      both.length === descs.length);
  yes('no other flag is touched', Object.keys(r.flags).every(function (k) { return r.flags[k] === 0x180; }));
  yes('the log says all of them took it', r.logged.length === 1 &&
      r.logged[0].indexOf(descs.length + ' of ' + descs.length + ' crime factions now ignore murder and assault') >= 0 &&
      r.logged[0].indexOf('REFUSED') < 0);
}
try {
  const r2 = run({ absent: ['2816c:Skyrim.esm'], throwOn: '267ea:Skyrim.esm', sticky: '2816b:Skyrim.esm' });
  yes('a faction missing from the load order is named, not skipped in silence',
      r2.logged[0].indexOf('not in this load order: CrimeFactionReach') >= 0);
  yes('one that throws is named as refused, with what it threw',
      r2.logged[0].indexOf('CrimeFactionWhiterun (Error: no SKSE)') >= 0);
  yes('one whose flags do not stay is named as refused',
      r2.logged[0].indexOf('CrimeFactionRift (the flags did not stay)') >= 0);
  yes('and the rest still took it', r2.logged[0].indexOf((descs.length - 3) + ' of ' + descs.length) >= 0);
} catch (e) {
  yes('the failures run (' + e + ')', false);
}

yes('it runs when a game is loaded, through guard', front.indexOf(END) >= 0);

// Nothing in game\ adds a bounty itself.
function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { walk(p, out); }
    else if (/\.js$/.test(e.name)) { out.push(p); }
  }
  return out;
}
const adds = [];
for (const file of walk(path.join(REPO_DIR, 'game'), [])) {
  const src = fs.readFileSync(file, 'utf8');
  const rx = /\.(modCrimeGold|setCrimeGold|setCrimeGoldViolent|sendAssaultAlarm)\s*\(/g;
  let m;
  while ((m = rx.exec(src)) !== null) { adds.push(path.relative(REPO_DIR, file) + ': ' + m[1]); }
}
for (const x of adds) { console.log('      adds a bounty: ' + x); }
yes('no gamemode, plugin or page code adds a bounty', adds.length === 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
