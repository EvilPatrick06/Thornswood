'use strict';
/*
  test-2551-building-holds.js

      node tests/test-2551-building-holds.js

  #2551, Patrick, 16 October, answer C: a Steward evicts and sets rent only
  in their own hold, with a table giving every claimable building the hold
  its door opens onto. scripts/dev/Build-BuildingHolds.py measures it out of
  the plugins into game/data/building-holds.json and the BUILDING_HOLD block
  of the gamemode. This holds all of it together:

    T  the table: every building the server claims is in it with one of the
       ten holds, or refused with the reason, never both; each answer
       follows the rule it says it followed
    G  the gamemode's BUILDING_HOLD block is the table, building for building
    X  DATA.cellToHold agrees with the table on every building it names, or
       the table says which is right and why
    B  the table was built against the collection's own bytes and the
       repository's own plugins, so a new revision or a content change
       without a rebuild turns this red
    S  the real eviction and rent over every building in the table: whoever
       keeps its hold (its Steward or its Jarl, isStewardOf, which
       test-offices.js and test-1638-office.js hold) ends a claim and sets
       rent there; whoever keeps any of the nine other holds is refused,
       told whose it is, and nothing changes; a building refused a hold is
       nobody's to settle; an admin with no role is no steward (staff hold
       no office by being staff, #2551)

  On a machine with the game (C:\Thornswood\Game\Data, or THORNSWOOD_DATA)
  holding the collection's bytes it also runs the builder with --check: the
  plugins give the committed table and block.
*/
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const read = (p) => fs.readFileSync(p, 'utf8').split(CR).join('').replace(/^\uFEFF/, '');
const TABLE = path.join(ROOT, 'game', 'data', 'building-holds.json');
const DATA = path.join(ROOT, 'game', 'data', 'data.json');
const DOORS = path.join(ROOT, 'game', 'data', 'doors.json');
const COLLECTION = path.join(ROOT, 'records', 'collection-plugins.json');
const LAST = path.join(ROOT, 'game', 'data', 'last-plugin.json');
const TOOL = path.join(ROOT, 'scripts', 'dev', 'Build-BuildingHolds.py');
const gm = read(path.join(ROOT, 'game', 'gamemode.js'));
const OURS = ['Thornswood-Content.esp', 'Thornswood-Last.esp', 'Thornswood-WoodworkerTrail.esp'];
const AFTER = ['Thornswood-Last.esp', 'Thornswood-WoodworkerTrail.esp'];
const HOLDS = ['whiterun', 'solitude', 'riften', 'markarth', 'windhelm',
               'falkreath', 'morthal', 'dawnstar', 'winterhold', 'ravenrock'];
const TOWN_OF_HOLD = {
  WhiterunHoldLocation: 'whiterun', HaafingarHoldLocation: 'solitude', RiftHoldLocation: 'riften',
  ReachHoldLocation: 'markarth', EastmarchHoldLocation: 'windhelm', FalkreathHoldLocation: 'falkreath',
  HjaalmarchHoldLocation: 'morthal', PaleHoldLocation: 'dawnstar', WinterholdHoldLocation: 'winterhold',
  DLC2SolstheimLocation: 'ravenrock'
};

let pass = 0, fail = 0;
function yes(w, c) { if (c) { pass++; console.log('PASS  ' + w); } else { fail++; console.log('FAIL  ' + w); } }
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}
function slice(src, start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}
/* One function out of src (the property block) by name, once, to the brace that closes it. */
function fnSrc(src, name) {
  if (!src) { return null; }
  const head = '\n  function ' + name + '(';
  const a = src.indexOf(head);
  if (a < 0 || src.indexOf(head, a + 1) >= 0) { return null; }
  const b = src.indexOf('{', a);
  let d = 0;
  for (let i = b; i < src.length; i++) {
    if (src[i] === '{') { d++; }
    else if (src[i] === '}') { d--; if (d === 0) { return src.slice(a + 1, i + 1); } }
  }
  return null;
}
function constObject(re) {
  const m = re.exec(gm);
  return m ? JSON.parse(m[1]) : null;
}

const table = JSON.parse(read(TABLE));
const rows = table.buildings || {};
const refused = table.refused || {};
const NAME = constObject(/\nconst BUILDING_NAME = (\{[^\n]*\});/);
const served = NAME ? Object.keys(NAME) : [];

// ---------------------------------------------------------------- T
yes('T1 the table is the builder\'s, for #2551', table.builtBy === 'scripts/dev/Build-BuildingHolds.py' && table.issue === 2551);
const doors = JSON.parse(read(DOORS));
yes('T2 the gamemode serves the buildings doors.json has (' + served.length + ')', served.length > 800 &&
    served.length === Object.keys(doors.buildings).length && served.every((b) => !!doors.buildings[b]));
const both = served.filter((b) => rows[b] && refused[b]);
const neither = served.filter((b) => !rows[b] && !refused[b]);
const extra = Object.keys(rows).concat(Object.keys(refused)).filter((b) => !NAME || !NAME[b]);
yes('T3 every one is in the table with a hold or refused, never both, and nothing else is' +
    (both.length + neither.length + extra.length ? ' (both ' + both.length + ', neither ' + neither.length + ', extra ' + extra.length + ')' : ''),
    served.length > 0 && both.length === 0 && neither.length === 0 && extra.length === 0);
const c = table.counts || {};
yes('T4 the counts are the rows: ' + Object.keys(rows).length + ' measured, ' + Object.keys(refused).length + ' refused',
    c.buildings === served.length && c.measured === Object.keys(rows).length && c.refused === Object.keys(refused).length &&
    c.byDoors + c.byDoorsOwnLocationPicks + c.byOwnLocation === c.measured);
yes('T5 every hold is one of the ten', Object.keys(rows).every((b) => HOLDS.indexOf(rows[b].hold) !== -1));
const holdLocs = table.holdLocations || {};
yes('T6 the ten hold locations are the records the rule reads, each to its hold',
    Object.keys(TOWN_OF_HOLD).every((e) => holdLocs[e] && holdLocs[e].hold === TOWN_OF_HOLD[e]) &&
    Object.keys(holdLocs).length === 10);
const placeHolds = (r) => Array.from(new Set((r.opensOnto || []).map((p) => p.hold).filter(Boolean))).sort();
const badRule = Object.keys(rows).filter((b) => {
  const r = rows[b];
  const hs = placeHolds(r);
  if (r.how === 'doors') { return !(hs.length === 1 && hs[0] === r.hold); }
  if (r.how === 'own location') { return !(hs.length === 0 && !!r.ownLocation); }
  return !(hs.length > 1 && hs.indexOf(r.hold) !== -1 && r.how === 'doors open onto ' + hs.join(' and ') + '; its own location picks');
});
yes('T7 each answer follows the rule it names: one hold where the doors open, or the building\'s own location ' +
    'between two, or its own location when the doors give none' + (badRule.length ? ' (not: ' + badRule.slice(0, 4).join(', ') + ')' : ''),
    badRule.length === 0);
const overOwn = Object.keys(rows).filter((b) => rows[b].ownLocationHold);
yes('T8 where the doors and the building\'s own location name two holds, the doors decide and the table says so (' +
    overOwn.length + ')', overOwn.every((b) => rows[b].how === 'doors' && rows[b].ownLocationHold !== rows[b].hold) &&
    c.doorsOverOwnLocation === overOwn.length);
yes('T9 every building refused says why, and names no hold', Object.keys(refused).every((b) =>
  typeof refused[b].why === 'string' && refused[b].why.length > 20 && !refused[b].hold));

// ---------------------------------------------------------------- G
const blockText = slice(gm, '  // ==== BUILDING_HOLD, generated ====', '  // ==== end BUILDING_HOLD ====');
const prop = slice(gm, '// ==== thornswood property ====', '// ==== end thornswood property ====');
yes('G1 the property block carries the BUILDING_HOLD block', !!blockText && !!prop && prop.indexOf(blockText) !== -1);
const m = blockText ? /\n  var BUILDING_HOLD = (\{[^\n]*\});\n/.exec(blockText) : null;
const inBlock = m ? JSON.parse(m[1]) : null;
yes('G2 the block is the table, building for building (' + (inBlock ? Object.keys(inBlock).length : 0) + ')', !!inBlock &&
    Object.keys(inBlock).length === Object.keys(rows).length &&
    Object.keys(rows).every((b) => inBlock[b] === rows[b].hold));

// ---------------------------------------------------------------- X
const c2h = JSON.parse(read(DATA)).cellToHold || {};
const named = served.filter((b) => Object.prototype.hasOwnProperty.call(c2h, b));
const disagree = (table.cellToHold && table.cellToHold.disagree) || {};
const wrong = named.filter((b) => TOWN_OF_HOLD[c2h[b]] !== (rows[b] ? rows[b].hold : undefined) &&
  !(disagree[b] && typeof disagree[b].right === 'string' && disagree[b].right.length > 20));
yes('X1 DATA.cellToHold names ' + named.length + ' of the buildings, and agrees with the table on each, or the table says ' +
    'which is right and why' + (wrong.length ? ' (not: ' + wrong.slice(0, 4).join(', ') + ')' : ''),
    named.length > 500 && wrong.length === 0);
yes('X2 and the table\'s own count of that is right', table.cellToHold && table.cellToHold.named === named.length &&
    table.cellToHold.agree === named.length - Object.keys(disagree).length);

// ---------------------------------------------------------------- B
const built = table.builtAgainst || [];
const record = JSON.parse(read(COLLECTION));
const rec = {};
for (const r of record.plugins) { rec[r.name.toLowerCase()] = r; }
const order = JSON.parse(read(LAST)).loadOrder.concat(AFTER);
yes('B1 the table records the bytes of every plugin of the load order it read (' + built.length + ')',
    built.length === order.length && built.every((r, i) => r.name === order[i] && /^[0-9a-f]{64}$/.test(r.sha256) && r.size > 0));
const other = built.filter((r) => OURS.indexOf(r.name) < 0 &&
  !(rec[r.name.toLowerCase()] && rec[r.name.toLowerCase()].sha256.toLowerCase() === r.sha256 && rec[r.name.toLowerCase()].size === r.size));
yes('B2 every plugin but ours is the collection\'s own bytes, revision ' + record.revision +
    (other.length ? ' (not: ' + other.slice(0, 4).map((r) => r.name).join(', ') + '; rebuild the table)' : ''), other.length === 0);
const stale = OURS.filter((n) => {
  const row = built.find((r) => r.name === n);
  const p = path.join(ROOT, 'game', 'content', n);
  return !row || !fs.existsSync(p) || row.sha256 !== crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
});
yes('B3 and ours are the repository\'s (rebuild the table after a content change)' +
    (stale.length ? ' (not: ' + stale.join(', ') + ')' : ''), stale.length === 0);

// ---------------------------------------------------------------- S
/*
  The real evict and rentCmd, with the real building names and holds, over
  a door register and the office readers as a table: who keeps which hold as
  a steward (Steward of it, or its Jarl).
*/
const LIFT = ['holdOfBuilding', 'notStewardHere', 'nameOf', 'evict', 'rentCmd'];
const lifted = LIFT.map((n) => fnSrc(prop, n));
const holdTown = slice(gm, '  var HOLD_TOWN = {', '};');
const officeAtDoor = /\n  var OFFICE_AT_DOOR = '[^\n]*';/.exec(gm);
yes('S0 the eviction, the rent and the building\'s hold are in the property block, each once' +
    (lifted.some((s) => !s) ? ' (missing: ' + LIFT.filter((n, i) => !lifted[i]).join(', ') + ')' : ''),
    lifted.every((s) => !!s) && !!holdTown && !!officeAtDoor && !!inBlock && !!NAME);

const OWNER = 7, STEW = 100, ADMIN = 500;
function steward(keeps) {
  const claims = {};
  let at = null;
  const said = [];
  const make = new Function('BUILDING_HOLD', 'BUILDING_NAME', 'claims', 'here', 'isSteward', 'isStewardOf',
    'holderOf', 'save', 'pushAll', 'plog', 'redrawPanel', 'rentDue', 'globalThis',
    holdTown + '\n' + officeAtDoor[0] + '\n' + lifted.join('\n') + '\nreturn { evict: evict, rentCmd: rentCmd };');
  const f = make(inBlock, NAME, claims, function () { return at; },
    function (pid) { return pid === STEW && keeps.length > 0; },
    function (pid, hold) { return pid === STEW && keeps.indexOf(hold) !== -1; },
    function (b) { return claims[b] || null; }, function () { }, function () { }, function () { }, function () { },
    function () { }, {});
  return {
    at: function (b) { at = b; claims[b] = { by: OWNER, name: 'Alice', at: 1, touched: Date.now() }; said.length = 0; },
    evict: function (pid) { f.evict(1, pid, function (p, m) { said.push(m); }); return said.slice(); },
    rent: function (pid, n) { f.rentCmd(['/rent', String(n)], 1, pid, function (p, m) { said.push(m); }); return said.slice(); },
    claims: claims
  };
}

if (lifted.every((s) => !!s) && holdTown && officeAtDoor && inBlock && NAME) {
  const keepers = {};
  HOLDS.forEach((h) => { keepers[h] = steward([h]); });
  let allowed = 0, refusedOk = 0, badIn = [], badOut = [];
  for (const b of Object.keys(rows)) {
    const h = rows[b].hold;
    // Its own hold's steward: the rent, then the eviction.
    const k = keepers[h];
    k.at(b);
    k.rent(STEW, 25);
    const rentSet = k.claims[b] && k.claims[b].rent && k.claims[b].rent.amount === 25;
    k.evict(STEW);
    if (rentSet && !k.claims[b]) { allowed++; } else { badIn.push(b); }
    // Every other hold's steward.
    for (const o of HOLDS) {
      if (o === h) { continue; }
      const s = keepers[o];
      s.at(b);
      const t1 = s.evict(STEW);
      const t2 = s.rent(STEW, 25);
      const town = { ravenrock: 'Raven Rock' }[h] || h.charAt(0).toUpperCase() + h.slice(1);
      const whose = NAME[b] + ' answers to ' + town + '. Only the Steward of ' + town + ' or its Jarl ends a claim or sets rent there.';
      if (s.claims[b] && s.claims[b].by === OWNER && !s.claims[b].rent && t1[0] === whose && t2[1] === whose) { refusedOk++; }
      else { badOut.push(b + ' by ' + o); }
    }
  }
  yes('S1 at every one of the ' + Object.keys(rows).length + ' buildings with a hold, the steward of that hold sets the rent ' +
      'and ends the claim' + (badIn.length ? ' (not: ' + badIn.slice(0, 3).join(', ') + ')' : ''), allowed === Object.keys(rows).length);
  yes('S2 and the steward of each of the nine other holds is refused both, told whose it is, and nothing changes (' +
      refusedOk + ' refusals)' + (badOut.length ? ' (not: ' + badOut.slice(0, 3).join(', ') + ')' : ''),
      refusedOk === Object.keys(rows).length * 9 && badOut.length === 0);
  let none = 0, noneBad = [];
  for (const b of Object.keys(refused)) {
    let ok = true;
    for (const h of HOLDS) {
      const s = keepers[h];
      s.at(b);
      const t = s.evict(STEW);
      s.rent(STEW, 25);
      if (!(s.claims[b] && !s.claims[b].rent &&
            t[0] === NAME[b] + ' answers to no hold the server knows, so no steward ends a claim or sets rent there.')) { ok = false; }
    }
    if (ok) { none++; } else { noneBad.push(b); }
  }
  yes('S3 at each of the ' + Object.keys(refused).length + ' buildings refused a hold, no steward of any hold ends a claim ' +
      'or sets rent, and each is told why' + (noneBad.length ? ' (not: ' + noneBad.slice(0, 3).join(', ') + ')' : ''),
      none === Object.keys(refused).length);
  const all = steward(HOLDS.slice());
  const breezehome = '165a8:Skyrim.esm';
  all.at(breezehome);
  all.evict(STEW);
  yes('S4 Breezehome is Whiterun\'s, and somebody who keeps all ten ends a claim there', rows[breezehome] &&
      rows[breezehome].hold === 'whiterun' && !all.claims[breezehome]);
  const nobody = steward([]);
  nobody.at(breezehome);
  const t = nobody.evict(ADMIN);
  const r = nobody.rent(ADMIN, 25);
  yes('S5 an admin with no role is no steward anywhere, as since #2551: staff hold no office by being staff (' + t[0] + ')',
      t[0] === 'Only a steward ends a claim.' && r[1] === 'Only a steward sets rent.' && !!nobody.claims[breezehome] &&
      !nobody.claims[breezehome].rent);
}

// ---------------------------------------------------------------- rebuild
function python(args) {
  for (const exe of ['python', 'py', 'python3']) {
    const p = spawnSync(exe, args, { encoding: 'utf8', maxBuffer: 1 << 26 });
    if (!p.error) { return p; }
  }
  return null;
}
const data = process.env.THORNSWOOD_DATA || 'C:\\Thornswood\\Game\\Data';
if (fs.existsSync(path.join(data, 'Skyrim.esm'))) {
  const run = python([TOOL, '--check', '--data', data]);
  const said = run ? run.stdout + run.stderr : '';
  if (run && run.status === 2) {
    console.log('SKIP  R1: the game at ' + data + ' is not the collection\'s load order:');
    console.log(said.split('\n').filter((l) => /STOP/.test(l)).join('\n'));
  } else {
    yes('R1 read again from the plugins at ' + data + ', every building gives the committed table and block',
        !!run && run.status === 0);
    if (!run || run.status !== 0) { console.log(said); }
  }
} else {
  console.log('SKIP  R1: no game at ' + data + ' (a machine with the game reads the plugins again)');
}
done();
