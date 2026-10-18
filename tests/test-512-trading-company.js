'use strict';
// Issue #512: the Free Skyrim Trading Company's terms as staff data
// (game/trading-company.js, game/data/trading-company.json). The file's numbers
// are gamemode.js's numbers, bad terms are refused, a proposal changes nothing,
// a haul keeps the cut it was posted under, and the #511 charter hook.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const tc = require('../game/trading-company');

let passed = 0;
function ok(name, fn) { fn(); passed++; }

const text = fs.readFileSync(path.join(__dirname, '../game/data/trading-company.json'), 'utf8');
const terms = tc.loadTerms(text);
const mode = fs.readFileSync(path.join(__dirname, '../game/gamemode.js'), 'utf8');

function num(name) {
  const m = new RegExp('var ' + name + ' = (\\d+);').exec(mode);
  assert.ok(m, 'gamemode.js still has ' + name);
  return Number(m[1]);
}
function fn(name, arg, consts) {
  const m = new RegExp('function ' + name + '\\(' + arg + '\\) \\{([\\s\\S]*?)\\n  \\}').exec(mode);
  assert.ok(m, 'gamemode.js still has ' + name);
  return new Function(...Object.keys(consts), arg, m[1]).bind(null, ...Object.values(consts));
}

ok('the file is UTF-8 without a BOM, and the module too', () => {
  assert.notEqual(text.charCodeAt(0), 0xFEFF);
  assert.notEqual(fs.readFileSync(path.join(__dirname, '../game/trading-company.js'), 'utf8').charCodeAt(0), 0xFEFF);
});

ok('the file checks', () => assert.deepEqual(tc.checkTerms(terms), []));

const HAUL_TENTH_FROM = num('HAUL_TENTH_FROM');
const SALE_CUT_FROM = num('SALE_CUT_FROM');
const JOB_FEE = num('JOB_FEE');
const haulTenth = fn('haulTenth', 'pay', { HAUL_TENTH_FROM });
const saleCutsNow = fn('saleCuts', 'price', { SALE_CUT_FROM });

ok('the haul fee is the board job fee a haul pays today', () => assert.equal(terms.haulFee, JOB_FEE));
ok('the haul cut is gamemode.js haulTenth for every pay 0..5000', () => {
  for (let p = 0; p <= 5000; p++) { assert.equal(tc.haulCut({ pay: p }, terms), haulTenth(p), 'pay ' + p); }
});
ok('the sale cuts are gamemode.js saleCuts for every price 0..5000', () => {
  for (let p = 0; p <= 5000; p++) { assert.deepEqual(tc.saleCuts(p, terms), saleCutsNow(p), 'price ' + p); }
});
ok('the shipped defaults: charter by the company, no freight', () => {
  assert.equal(terms.charter, 'company');
  assert.equal(terms.freightPerLoad, 0);
  assert.deepEqual(tc.freightFor(terms), { gold: 0, to: 'ledger' });
});

function bad(change, why) {
  const t = Object.assign({}, terms, change);
  assert.ok(tc.checkTerms(t).length > 0, why);
  assert.throws(() => tc.loadTerms(JSON.stringify(t)), /refused/, why);
}
ok('bad terms are refused, never defaulted', () => {
  bad({ haulFee: -1 }, 'negative fee');
  bad({ haulFee: 1.5 }, 'fraction of gold');
  bad({ haulFee: '30' }, 'a string');
  bad({ haulCutPercent: 101 }, 'over 100');
  bad({ saleWorkerPercent: 60, saleGonePercent: 41 }, 'sale cuts over the price');
  bad({ charter: 'jarl' }, 'unknown charter rule');
  bad({ freightTo: 'pocket' }, 'unknown freight destination');
  bad({ extra: 1 }, 'unknown key');
  bad({ v: 2 }, 'version');
  const missing = Object.assign({}, terms); delete missing.saleCutFrom;
  assert.ok(tc.checkTerms(missing).some(s => /Missing/.test(s)));
  assert.throws(() => tc.loadTerms('{not json'), /not readable/);
  assert.throws(() => tc.haulCut({ pay: 100 }, Object.assign({}, terms, { haulCutPercent: -5 })), /refused/);
});

ok('a sale with both cuts at 50 leaves the seller nothing and never less', () => {
  const t = Object.assign({}, terms, { saleWorkerPercent: 50, saleGonePercent: 50 });
  for (let p = 0; p <= 999; p++) {
    const s = tc.saleCuts(p, t);
    assert.ok(s.seller >= 0);
    assert.equal(s.worker + s.gone + s.seller, s.price);
  }
});

ok('a haul keeps the cut it was posted under', () => {
  const posted = tc.stampHaul({ pay: 100, dest: 'Windhelm' }, terms);
  assert.deepEqual(posted.cut, { percent: 10, from: 10 });
  const raised = Object.assign({}, terms, { haulCutPercent: 25 });
  assert.equal(tc.haulCut(posted, raised), 10, 'paid as posted');
  assert.equal(tc.haulCut(tc.stampHaul({ pay: 100 }, raised), raised), 25, 'a new haul pays the new cut');
  assert.equal(tc.haulCut({ pay: 100 }, raised), 25, 'a haul from before stamps reads the current terms');
  assert.equal(tc.haulCut({ pay: 9 }, terms), 0);
  assert.equal(tc.haulCut({ pay: 'x' }, terms), 0);
  assert.equal(posted.dest, 'Windhelm', 'the stamp leaves the rest of the haul alone');
});

ok('the charter hook reads the setting', () => {
  const co = { company: true }, staff = { staff: true }, nobody = {};
  assert.equal(tc.mayCharter(co, terms), true);
  assert.equal(tc.mayCharter(staff, terms), true, 'an admin testing counts as the company');
  assert.equal(tc.mayCharter(nobody, terms), false);
  assert.equal(tc.mayCharter(null, terms), false);
  const anyone = Object.assign({}, terms, { charter: 'anyone' });
  assert.equal(tc.mayCharter(nobody, anyone), true);
  const st = Object.assign({}, terms, { charter: 'staff' });
  assert.equal(tc.mayCharter(co, st), false);
  assert.equal(tc.mayCharter(staff, st), true);
  assert.equal(tc.mayCharter({ company: 'yes' }, terms), false, 'only a real true counts');
});

ok('a proposal changes nothing; staff confirm it', () => {
  const state = { terms: tc.loadTerms(text), history: [] };
  const before = JSON.stringify(state);
  const next = Object.assign({}, state.terms, { haulFee: 40, freightPerLoad: 5 });
  const p = tc.proposeTerms(state.terms, next, [{ pay: 50 }, { pay: 80 }]);
  assert.equal(p.ok, true);
  assert.deepEqual(p.changes, [{ term: 'haulFee', from: 30, to: 40 }, { term: 'freightPerLoad', from: 0, to: 5 }]);
  assert.equal(p.openHaulsKeepTerms, 2);
  assert.equal(JSON.stringify(state), before, 'proposing touched nothing');
  next.haulFee = 999;
  assert.equal(p.next.haulFee, 40, 'the proposal is its own copy');
  const after = tc.adoptTerms(state, p, 'staff:1', 1000);
  assert.equal(after.terms.haulFee, 40);
  assert.equal(after.history.length, 1);
  assert.deepEqual(after.history[0], { at: 1000, by: 'staff:1', changes: p.changes });
  assert.equal(JSON.stringify(state), before, 'adopting returns new state');
  assert.throws(() => tc.adoptTerms(after, p, 'staff:1', 1001), /changed since/, 'a stale proposal');
  assert.throws(() => tc.adoptTerms(state, p, '', 1001), /names who/);
  assert.throws(() => tc.adoptTerms(state, p, 'staff:1', -1), /says when/);
  const same = tc.proposeTerms(state.terms, state.terms, []);
  assert.throws(() => tc.adoptTerms(state, same, 'staff:1', 1), /changes nothing/);
  const refused = tc.proposeTerms(state.terms, Object.assign({}, state.terms, { haulFee: -3 }), []);
  assert.equal(refused.ok, false);
  assert.ok(refused.why.length > 0);
  assert.throws(() => tc.adoptTerms(state, refused, 'staff:1', 1), /refused/);
});

ok('nothing in the module names a person, a hold, a port or a time', () => {
  const src = fs.readFileSync(path.join(__dirname, '../game/trading-company.js'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  for (const word of ['Solitude', 'Windhelm', 'Dawnstar', 'Haafingar', 'Eastmarch', 'Date.now', 'setTimeout', 'setInterval']) {
    assert.ok(src.indexOf(word) < 0, word);
  }
});

console.log('test-512-trading-company: ' + passed + ' passed, 0 failed');
