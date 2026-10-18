'use strict';
/*
  test-511-trade-cargo.js

      node tests/test-511-trade-cargo.js

  #511, trade ships. The manifest in game/trade-cargo.js is the part of the
  design that does not wait on Patrick (issuecomment-6245473792): what is in a
  hold, whose pack each piece came out of, who it is for, and where it went.
  The rule the issue names is that a cargo worth robbing must never be a
  cargo made out of nothing, so most of this file tries to make one grow:

  - nothing is written aboard without the receipt of a debit, and one receipt
    loads once;
  - coin is not cargo;
  - a piece leaves in two steps (begin, then finish with the credit's
    receipt), and a crash between them keeps it counted;
  - only the person it is for receives it at the far end, only the loader
    takes it back where it was loaded, and nothing but taking happens at sea;
  - a refused change leaves the state as it was;
  - saved state that has been tampered with is refused, never started empty.

  - the ports, routes, leg times and crews are staff data, never code: a bad
    list is refused whole, and an edit is first a proposal that says what it
    would change and which holds it would strand (Patrick, 17 Oct, 10:13 PM
    MT: the server proposes, staff confirm, players decide).

  The ports here are stand-ins written as staff would write them.
  Read only: no world, no files.
*/
const path = require('path');
const { createTradeCargo, checkRoutes, proposeRoutes, GOLD_BASE } = require(path.join(__dirname, '..', 'game', 'trade-cargo.js'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function refused(what, fn, re) {
  let err = null;
  try { fn(); } catch (e) { err = e; }
  yes(what, !!err && (!re || re.test(String(err.message))));
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const ships = createTradeCargo({ ports: ['solitude', 'windhelm', 'dawnstar'] });
const s = ships.empty();

// ------------------------------------------------------------- setting up
refused('a ship needs two ports', () => createTradeCargo({ ports: ['solitude'] }));
refused('a port is named once', () => createTradeCargo({ ports: ['solitude', 'solitude'] }));
yes('the line limit is a trade side, 24, unless told otherwise', ships.MAX_LINES === 24);
ships.open(s, 'red-wave', 'solitude');
refused('a hold is opened once', () => ships.open(s, 'red-wave', 'solitude'), /already/);
refused('a hold opens only at a port on the list', () => ships.open(s, 'ghost', 'riften'), /No port/);

// ------------------------------------------------------------- loading
const sword = { baseId: 0x13989, count: 1, health: 0.85, name: 'Steel Sword' };
const ore = { baseId: 0x5acdb, count: 20 };
const l1 = ships.load(s, 'red-wave', { by: 'Brynja', for: 'Ulfric Trader', receipt: 'debit:1', entry: sword });
const l2 = ships.load(s, 'red-wave', { by: 'Brynja', for: 'Ulfric Trader', receipt: 'debit:2', entry: ore });
yes('two lines go aboard', ships.aboard(s, 'red-wave').length === 2);
yes('a piece keeps every field it had, condition and name included',
    same(ships.aboard(s, 'red-wave')[0].entry, sword));
refused('one debit loads once', () =>
  ships.load(s, 'red-wave', { by: 'Brynja', for: 'Ulfric Trader', receipt: 'debit:1', entry: ore }), /already used/);
refused('nothing goes aboard without a receipt', () =>
  ships.load(s, 'red-wave', { by: 'Brynja', for: 'Ulfric Trader', entry: ore }), /receipt/);
refused('coin is not cargo', () =>
  ships.load(s, 'red-wave', { by: 'Brynja', for: 'Ulfric Trader', receipt: 'debit:g', entry: { baseId: GOLD_BASE, count: 100 } }), /Coin/);
refused('a count of nothing is not a piece', () =>
  ships.load(s, 'red-wave', { by: 'Brynja', for: 'X', receipt: 'debit:0', entry: { baseId: 0x5acdb, count: 0 } }));
refused('a load names who it is for', () =>
  ships.load(s, 'red-wave', { by: 'Brynja', receipt: 'debit:9', entry: ore }));
yes('the refused loads used no receipt', !('debit:g' in s.receipts) && !('debit:0' in s.receipts) && !('debit:9' in s.receipts));

{
  const small = createTradeCargo({ ports: ['a', 'b'], maxLines: 2 });
  const t = small.empty();
  small.open(t, 'h', 'a');
  small.load(t, 'h', { by: 'P', for: 'Q', receipt: 'r1', entry: ore });
  small.load(t, 'h', { by: 'P', for: 'Q', receipt: 'r2', entry: ore });
  refused('a full hold takes no more', () => small.load(t, 'h', { by: 'P', for: 'Q', receipt: 'r3', entry: ore }), /full/);
}

// ------------------------------------------------------------- leaving early
refused('nobody else takes it back at the dock it was loaded at', () =>
  ships.begin(s, 'red-wave', l2, 1, 'returned', 'Ulfric Trader', 10), /loaded it/);
refused('it is not delivered at the port it was loaded in', () =>
  ships.begin(s, 'red-wave', l2, 1, 'delivered', 'Ulfric Trader', 10), /far end/);
{
  const r = ships.begin(s, 'red-wave', l2, 5, 'returned', 'Brynja', 10);
  yes('the loader takes five ore back where they loaded it', r.entry.count === 5 && r.entry.baseId === ore.baseId);
  ships.finish(s, 'red-wave', r.out, 'credit:1');
  yes('and fifteen are left aboard', ships.aboard(s, 'red-wave')[1].entry.count === 15);
}

// ------------------------------------------------------------- the voyage
refused('a voyage goes somewhere else', () => ships.depart(s, 'red-wave', 'solitude', 100, 200), /No voyage/);
refused('a voyage arrives after it leaves', () => ships.depart(s, 'red-wave', 'windhelm', 200, 200), /later/);
{
  const pend = ships.begin(s, 'red-wave', l2, 1, 'returned', 'Brynja', 20);
  refused('a hold does not sail with something half handed out', () => ships.depart(s, 'red-wave', 'windhelm', 100, 200), /handed out/);
  ships.undo(s, 'red-wave', pend.out);
  yes('a refused credit puts the piece back aboard', ships.aboard(s, 'red-wave')[1].entry.count === 15);
}
ships.depart(s, 'red-wave', 'windhelm', 100, 1900);
refused('a hold at sea takes no cargo', () =>
  ships.load(s, 'red-wave', { by: 'Brynja', for: 'X', receipt: 'debit:3', entry: ore }), /at sea/);
refused('nothing is delivered at sea', () => ships.begin(s, 'red-wave', l1, 1, 'delivered', 'Ulfric Trader', 500), /at sea/);
yes('before its time it is still at sea', same(ships.arrive(s, 1899), []) && s.holds['red-wave'].sailing !== null);
yes('at its time it docks at Windhelm', same(ships.arrive(s, 1900), ['red-wave']) &&
    s.holds['red-wave'].port === 'windhelm' && s.holds['red-wave'].sailing === null);

// ------------------------------------------------------------- the far end
refused('only the person it is for receives it', () => ships.begin(s, 'red-wave', l1, 1, 'delivered', 'Brynja', 2000), /person it is for/);
refused('the loader cannot take it back at the far end', () => ships.begin(s, 'red-wave', l1, 1, 'returned', 'Brynja', 2000), /where it was loaded/);
refused('no more leaves than is aboard', () => ships.begin(s, 'red-wave', l2, 16, 'delivered', 'Ulfric Trader', 2000), /not that much/);
{
  const d = ships.begin(s, 'red-wave', l1, 1, 'delivered', 'Ulfric Trader', 2000);
  yes('the sword arrives as it was loaded', same(d.entry, sword));
  yes('while it is being handed out it is still counted', ships.audit(s).pending === 1);
  refused('one credit receipt finishes once', () => { ships.finish(s, 'red-wave', d.out, 'credit:1'); }, /already used/);
  ships.finish(s, 'red-wave', d.out, 'credit:2');
  refused('a finished hand out cannot finish again', () => ships.finish(s, 'red-wave', d.out, 'credit:3'), /Nothing is waiting/);
  const t = ships.begin(s, 'red-wave', l2, 10, 'taken', 'A Stranger', 2100);
  ships.finish(s, 'red-wave', t.out, 'credit:4');
  const left = ships.begin(s, 'red-wave', l2, 5, 'left', 'Ulfric Trader', 2200);
  ships.finish(s, 'red-wave', left.out, 'drop:windhelm:1');
}
{
  const a = ships.audit(s);
  yes('the books balance: 21 loaded, 5 returned, 1 delivered, 10 taken, 5 left, none aboard',
      a.aboard === 0 && a.pending === 0 && a.out === 21);
}
refused('an empty hold does not sail', () => ships.depart(s, 'red-wave', 'solitude', 3000, 4000), /empty/);

// ------------------------------------------------------------- taking at sea is the caller's rule
{
  const t = ships.empty();
  ships.open(t, 'maiden', 'windhelm');
  const l = ships.load(t, 'maiden', { by: 'Gjalund', for: 'Raven', receipt: 'd1', entry: ore });
  ships.depart(t, 'maiden', 'dawnstar', 0, 10);
  const r = ships.begin(t, 'maiden', l, 3, 'taken', 'Raider', 5);
  yes('this file lets a hold at sea be taken from; when is for the world to decide, not this file', r.entry.count === 3);
}

// ------------------------------------------------------------- a refused change changes nothing
{
  const before = JSON.stringify(s);
  try { ships.begin(s, 'red-wave', l2, 1, 'delivered', 'Ulfric Trader', 1); } catch (e) { /* refused */ }
  try { ships.load(s, 'red-wave', { by: 'B', for: 'C', receipt: 'credit:2', entry: ore }); } catch (e) { /* refused */ }
  yes('refused changes leave the state byte for byte', JSON.stringify(s) === before);
}

// ------------------------------------------------------------- saving
{
  const t = ships.empty();
  ships.open(t, 'h', 'solitude');
  const l = ships.load(t, 'h', { by: 'P', for: 'Q', receipt: 'd1', entry: ore });
  ships.begin(t, 'h', l, 2, 'returned', 'P', 1);
  const kept = ships.save(t);
  const back = ships.parse(kept);
  yes('a save reads back the same, a pending hand out included', ships.save(back) === kept && ships.audit(back).pending === 2);

  function tamper(what, edit) {
    const x = JSON.parse(kept); edit(x);
    refused('a save is refused when ' + what, () => ships.parse(JSON.stringify(x)));
  }
  tamper('a line grew', x => { x.holds.h.lines[l].aboard = 30; });
  tamper('a line\'s piece grew', x => { x.holds.h.lines[l].entry.count = 25; });
  tamper('a pending hand out vanished', x => { x.holds.h.outs = []; });
  tamper('a receipt is missing from the list', x => { x.receipts = {}; });
  tamper('a receipt nothing uses is on the list', x => { x.receipts.spare = true; });
  tamper('the cargo turned to gold', x => { x.holds.h.lines[l].entry.baseId = GOLD_BASE; });
  tamper('the hold is at an unknown port', x => { x.holds.h.port = 'riften'; });
  tamper('it is not a manifest at all', x => { delete x.v; });
  refused('a save that is not JSON is refused', () => ships.parse('{'), /cannot be verified/);
  refused('nothing saved is refused, not started empty', () => ships.parse(''), /cannot be verified/);
}

// ------------------------------------------------------------- staff data
{
  const port = (key, name, hold, x) => ({ key, name, hold, world: '3c:Skyrim.esm', pos: [x, 0, 0] });
  const cfg = { v: 1,
    ports: [port('solitude', 'Solitude docks', 'solitude', 1), port('windhelm', 'Windhelm docks', 'windhelm', 2)],
    routes: [{ from: 'solitude', to: 'windhelm', minutes: 30, crew: ['fb18:CFTO.esp'] }] };
  const ok = checkRoutes(cfg);
  yes('staff routes read back as written', ok.ports.length === 2 && ok.routes[0].minutes === 30 && ok.routes[0].crew[0] === 'fb18:CFTO.esp');
  yes('an empty list is a world with no ships, not an error', checkRoutes({ v: 1, ports: [], routes: [] }).routes.length === 0);
  yes('a route with no crew is allowed', checkRoutes({ v: 1, ports: cfg.ports, routes: [{ from: 'windhelm', to: 'solitude', minutes: 45 }] }).routes[0].crew.length === 0);
  const bad = (what, edit) => { const x = JSON.parse(JSON.stringify(cfg)); edit(x); refused('staff routes are refused whole when ' + what, () => checkRoutes(x)); };
  bad('a route names a port that is not on the list', x => { x.routes[0].to = 'dawnstar'; });
  bad('a port is listed twice', x => { x.ports.push(x.ports[0]); });
  bad('a route is listed twice', x => { x.routes.push(x.routes[0]); });
  bad('a leg takes no time', x => { x.routes[0].minutes = 0; });
  bad('a leg is longer than a week', x => { x.routes[0].minutes = 7 * 24 * 60 + 1; });
  bad('a port is in no hold', x => { x.ports[0].hold = 'cyrodiil'; });
  bad('a crew member is not a reference', x => { x.routes[0].crew = ['Captain']; });
  bad('a field nobody reads is added', x => { x.schedule = 'noon'; });

  const ships2 = createTradeCargo({ ports: ok.ports.map(p => p.key), routes: ok.routes });
  const t = ships2.empty();
  ships2.open(t, 'h', 'windhelm');
  ships2.load(t, 'h', { by: 'P', for: 'Q', receipt: 'r', entry: ore });
  refused('with staff routes in force, a hold sails only a route staff listed', () => ships2.depart(t, 'h', 'solitude', 0, 10), /No voyage/);
  {
    const u = ships.empty();
    ships.open(u, 'm', 'solitude');
    ships.load(u, 'm', { by: 'P', for: 'Q', receipt: 'r', entry: ore });
    refused('staff cannot amend a voyage that has not started', () => ships.amend(u, 'm', { arriveAt: 50 }), /not at sea/);
    ships.depart(u, 'm', 'windhelm', 0, 100);
    ships.amend(u, 'm', { to: 'dawnstar', arriveAt: 500 });
    yes('staff can turn a ship to another port and another time, for the story', u.holds.m.sailing.to === 'dawnstar' && u.holds.m.sailing.arriveAt === 500);
    refused('but not back to where it left', () => ships.amend(u, 'm', { to: 'solitude' }), /No voyage/);
    refused('and not to arrive before it left', () => ships.amend(u, 'm', { arriveAt: 0 }), /after it left/);
    yes('and what is aboard is untouched', ships.aboard(u, 'm')[0].entry.count === 20 && same(ships.arrive(u, 499), []) && same(ships.arrive(u, 500), ['m']));
  }

  const edit = { v: 1, ports: [cfg.ports[0], port('dawnstar', 'Dawnstar docks', 'dawnstar', 3)],
    routes: [{ from: 'solitude', to: 'dawnstar', minutes: 40 }] };
  const p = proposeRoutes(cfg, edit, t);
  yes('a proposal names every change for staff to confirm',
      p.changes.some(l => /Add the port Dawnstar/.test(l)) && p.changes.some(l => /Remove the port Windhelm/.test(l)) &&
      p.changes.some(l => /Add the route solitude to dawnstar, 40/.test(l)) && p.changes.some(l => /Remove the route solitude to windhelm/.test(l)));
  yes('and names the hold it would strand', p.strands.length === 1 && /h is at windhelm/.test(p.strands[0]));
  yes('a proposal changes nothing by itself', checkRoutes(cfg).ports.length === 2 && t.holds.h.port === 'windhelm');
  refused('a proposal of a bad list is refused', () => proposeRoutes(cfg, { v: 1, ports: [], routes: [{ from: 'a', to: 'b', minutes: 1 }] }, null));
}

// ------------------------------------------------------------- boundaries
{
  const src = require('fs').readFileSync(path.join(__dirname, '..', 'game', 'trade-cargo.js'), 'utf8');
  yes('the manifest never asks the merchant trading code (#1373)', !/merchant-|MERCHANT_/.test(src.replace(/\/\*[\s\S]*?\*\//g, '')));
  yes('and never touches the world or a pack itself', !/\bmp\.|addItem|takeItem|require\(/.test(src.replace(/\/\*[\s\S]*?\*\//g, '')));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
