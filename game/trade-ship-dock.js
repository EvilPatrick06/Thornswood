'use strict';
/*
  TRADE SHIPS: THE DOCK, THE STAFF PANEL AND THE CLOCK (#2700, split from #511).

  game\trade-cargo.js is the manifest and the staff list of ports and routes.
  This file is what a person meets in the world, as views and as the words the
  panel sends back, and it never touches the world itself: the trade ships
  block of gamemode.js hands it what the server knows and does what it says.

  PATRICK'S ANSWERS (18 Oct 2026, 11:30 AM MT, via Smeagle; #2700):
    1. Staff edit ports, routes and crews in an in-game staff panel.
    2. A ship at the dock is a crate, with no new plugin.
    3. Arrivals happen on their own.
    4. Coin cannot be cargo.
    5. One hold carries 24 lines.

  THE CRATE. A port's crate is a container already in the world that staff
  picked (its reference, port.crate in the staff list). E on it opens the dock
  panel and never the container, so what the engine keeps in it is never
  cargo and no record is added to any plugin. portOfCrate() answers which
  port a pressed reference is.

  THE STAFF PANEL. Staff edit a draft of the list in force (editDraft); an edit
  changes nothing in force. The server proposes (staffView, through
  trade-cargo's proposeRoutes: every change and every hold the draft would
  strand) and staff confirm. A confirm names the list it was proposed against
  (baseOf), and one made against a list that has changed since is refused.

  THE CLOCK. A voyage takes the minutes staff gave its route (voyage), so
  nothing here says how long anything takes. nextArrival() is the earliest
  arrival among the holds at sea, for the one timer the block keeps; the
  manifest's arrive() docks every hold that is due. Nobody confirms an
  arrival and nobody is told: people find out at the dock.

  COIN. isCoin() is the one test; the dock never offers gold out of a pack and
  a load of it is refused before the pack is touched. trade-cargo refuses it
  again.

  THE CHARTER (#512). Loading and sailing are a charter; charterOf() is the one
  place it is asked, through the Trading Company's mayCharter(who, terms)
  (game\trading-company.js, #2687). who is { company, staff }: the Trading
  Company role and an admin. Collecting what was shipped to you, or taking
  back your own where you loaded it, is not a charter. With no company rule
  running, nobody charters, and the panel says why.

  WHAT IT NEVER DECIDES. Who sails, where, when or for how long: those are the
  players' RP (Patrick, 17 Oct 2026, 10:13 PM MT). Ports, routes, minutes and
  crews are staff data. Taking cargo that is not yours, and leaving goods in a
  drop box for somebody who never comes, wait on their own answer (#2700).
*/

var GOLD_BASE = 15;
var MINUTE = 60 * 1000;
var KEY_RE = /^[a-z0-9][a-z0-9:_.-]{0,63}$/;
var HOLD_KEYS = ['whiterun', 'solitude', 'riften', 'markarth', 'windhelm', 'falkreath',
  'morthal', 'dawnstar', 'winterhold', 'ravenrock'];
var NO_CHARTER = 'The Trading Company\'s charter rule is not running on this server yet, so nobody can load or sail a ship.';
var BAD_TERMS = 'The Trading Company\'s terms could not be read, so nobody can load or sail a ship until staff put them right.';
var NOT_CHARTERED = 'Only those the Trading Company charters may load or sail a ship.';

function copy(v) { return JSON.parse(JSON.stringify(v)); }
function isObj(v) { return !!v && typeof v === 'object' && !Array.isArray(v); }
function whole(n) { return Number.isInteger(n) && n > 0; }
function hex(n) { return (Number(n) >>> 0).toString(16); }
function same(a, b) { return !!a && !!b && a.actor === b.actor && a.profile === b.profile; }

function isCoin(baseId) { return (Number(baseId) >>> 0) === GOLD_BASE; }

/* A short, stable name for the list in force, so a confirm says what it was proposed against. */
function baseOf(routes) {
  var s = JSON.stringify(routes), h = 5381;
  for (var i = 0; i < s.length; i++) { h = ((h * 33) ^ s.charCodeAt(i)) >>> 0; }
  return h.toString(36) + '.' + s.length.toString(36);
}

function routeOf(routes, from, to) {
  var list = (routes && routes.routes) || [];
  for (var i = 0; i < list.length; i++) {
    if (list[i].from === from && list[i].to === to) { return list[i]; }
  }
  return null;
}
function portOf(routes, key) {
  var list = (routes && routes.ports) || [];
  for (var i = 0; i < list.length; i++) { if (list[i].key === key) { return list[i]; } }
  return null;
}

/* The port whose crate this reference is, or ''. */
function portOfCrate(routes, desc) {
  if (typeof desc !== 'string' || !desc) { return ''; }
  var d = desc.toLowerCase();
  var list = (routes && routes.ports) || [];
  for (var i = 0; i < list.length; i++) {
    if (typeof list[i].crate === 'string' && list[i].crate.toLowerCase() === d) { return list[i].key; }
  }
  return '';
}

/* When a voyage leaves and arrives: now, and now plus its route's minutes. */
function voyage(routes, from, to, now) {
  var r = routeOf(routes, from, to);
  if (!r) { throw new Error('No ship sails from here to there.'); }
  if (!Number.isInteger(now) || now < 0) { throw new Error('The time cannot be verified.'); }
  return { at: now, arriveAt: now + r.minutes * MINUTE };
}

/* The earliest arrival among the holds at sea, or null when none is. */
function nextArrival(state) {
  var next = null;
  var holds = (state && state.holds) || {};
  Object.keys(holds).forEach(function (id) {
    var s = holds[id] && holds[id].sailing;
    if (s && Number.isInteger(s.arriveAt) && (next === null || s.arriveAt < next)) { next = s.arriveAt; }
  });
  return next;
}

/*
  THE CHARTER, ASKED IN ONE PLACE. tc is what the Trading Company publishes:
  { mayCharter(who, terms), terms() } (#2687). Answers { may, why }.
*/
function charterOf(tc, who) {
  if (!tc || typeof tc.mayCharter !== 'function') { return { may: false, why: NO_CHARTER }; }
  var w = { company: !!(who && who.company === true), staff: !!(who && who.staff === true) };
  var may = false;
  try {
    var terms = typeof tc.terms === 'function' ? tc.terms() : tc.terms;
    may = tc.mayCharter(w, terms) === true;
  } catch (e) {
    return { may: false, why: BAD_TERMS };
  }
  return may ? { may: true, why: '' } : { may: false, why: NOT_CHARTERED };
}

/*
  THE PANEL'S WORDS. Sent by game\ui\thornswood-ship.js, never typed (Patrick,
  4 Oct: no chat commands for what people do). Answers { verb, ... } or
  { why } for anything it does not know.

    /ship close
    /ship load <hold> <base hex> <nth> <count> <for actor hex>
    /ship sail <hold> <port>
    /ship collect <hold> <line> <count>
    /ship return <hold> <line> <count>
    /ship staff
    /ship draft <edit ...>           see editDraft
    /ship confirm <base>
    /ship add <port>                 a new hold (ship) at a port, staff only
*/
function parse(parts) {
  var p = Array.isArray(parts) ? parts.map(function (x) { return String(x); }) : [];
  var verb = String(p[1] || '').toLowerCase();
  var n = function (s) { return /^[0-9]{1,9}$/.test(String(s)) ? Number(s) : NaN; };
  var h = function (s) { return /^[0-9a-f]{1,8}$/i.test(String(s)) ? parseInt(s, 16) >>> 0 : NaN; };
  var key = function (s) { return typeof s === 'string' && KEY_RE.test(s) ? s : ''; };
  if (verb === 'close' || verb === 'staff') { return { verb: verb }; }
  if (verb === 'load') {
    var l = { verb: 'load', hold: key(p[2]), base: h(p[3]), nth: n(p[4]), count: n(p[5]), forActor: h(p[6]) };
    if (!l.hold || !whole(l.base) || !Number.isInteger(l.nth) || !whole(l.count) || !whole(l.forActor)) { return { why: 'That load cannot be read.' }; }
    return l;
  }
  if (verb === 'sail') {
    var s = { verb: 'sail', hold: key(p[2]), to: key(p[3]) };
    return s.hold && s.to ? s : { why: 'That voyage cannot be read.' };
  }
  if (verb === 'collect' || verb === 'return') {
    var c = { verb: verb, hold: key(p[2]), line: n(p[3]), count: n(p[4]) };
    return c.hold && whole(c.line) && whole(c.count) ? c : { why: 'That cannot be read.' };
  }
  if (verb === 'draft') { return { verb: 'draft', edit: p.slice(2) }; }
  if (verb === 'confirm') { return p[2] ? { verb: 'confirm', base: String(p[2]) } : { why: 'That confirm cannot be read.' }; }
  if (verb === 'add') {
    var a = { verb: 'add', port: key(p[2]) };
    return a.port ? a : { why: 'Say which port.' };
  }
  return { why: 'The ship does not know that.' };
}

/*
  A STAFF EDIT TO THE DRAFT. Answers the next draft, checked whole by
  trade-cargo's checkRoutes, or throws what is wrong. crate is the container
  this staff member opened in the last minute, { desc, world, pos }, or null.

    port <key> <hold> <name ...>     a port at that crate
    crate <key>                      that port's crate is now the one opened
    unport <key>                     the port off the list
    route <from> <to> <minutes>      a one way route, or its new minutes
    unroute <from> <to>              the route off the list
    crew <from> <to> <ref ...>       the route's crew references; none is no crew
    reset                            the draft back to the list in force
*/
function editDraft(cargo, inForce, draft, edit, crate) {
  var d = copy(draft || inForce);
  var e = Array.isArray(edit) ? edit.map(String) : [];
  var op = (e[0] || '').toLowerCase();
  function needCrate() {
    if (!isObj(crate) || typeof crate.desc !== 'string' || typeof crate.world !== 'string' || !Array.isArray(crate.pos)) {
      throw new Error('Open the crate first, then press this within a minute.');
    }
    if (!/^[0-9a-f]{1,8}:[^:\s][^:]{0,95}$/i.test(crate.desc)) {
      throw new Error('That container is not one of the world\'s own, so it cannot be a dock.');
    }
    var taken = portOfCrate(d, crate.desc);
    if (taken) { throw new Error('That crate is already the dock of ' + taken + '.'); }
    return crate;
  }
  if (op === 'reset') { return cargo.checkRoutes(inForce); }
  if (op === 'port') {
    var c = needCrate();
    if (!e[1] || portOf(d, e[1])) { throw new Error('A port needs a new plain name.'); }
    if (HOLD_KEYS.indexOf(e[2]) < 0) { throw new Error('A port is in one of the holds.'); }
    var name = e.slice(3).join(' ').trim();
    d.ports.push({ key: e[1], name: name, hold: e[2], world: c.world, pos: c.pos.slice(0, 3), crate: c.desc });
  } else if (op === 'crate') {
    var c2 = needCrate();
    var pc = portOf(d, e[1]);
    if (!pc) { throw new Error('No port ' + e[1] + ' in the draft.'); }
    pc.crate = c2.desc; pc.world = c2.world; pc.pos = c2.pos.slice(0, 3);
  } else if (op === 'unport') {
    if (!portOf(d, e[1])) { throw new Error('No port ' + e[1] + ' in the draft.'); }
    d.ports = d.ports.filter(function (p) { return p.key !== e[1]; });
    d.routes = d.routes.filter(function (r) { return r.from !== e[1] && r.to !== e[1]; });
  } else if (op === 'route') {
    var m = /^[0-9]{1,6}$/.test(e[3] || '') ? Number(e[3]) : NaN;
    var r = routeOf(d, e[1], e[2]);
    if (r) { r.minutes = m; } else { d.routes.push({ from: e[1], to: e[2], minutes: m, crew: [] }); }
  } else if (op === 'unroute') {
    if (!routeOf(d, e[1], e[2])) { throw new Error('No route from ' + e[1] + ' to ' + e[2] + ' in the draft.'); }
    d.routes = d.routes.filter(function (x) { return !(x.from === e[1] && x.to === e[2]); });
  } else if (op === 'crew') {
    var rc = routeOf(d, e[1], e[2]);
    if (!rc) { throw new Error('No route from ' + e[1] + ' to ' + e[2] + ' in the draft.'); }
    rc.crew = e.slice(3);
  } else {
    throw new Error('The staff panel does not know that edit.');
  }
  return cargo.checkRoutes(d);
}

/*
  WHAT STAFF SEE: the list in force, the draft, and the server's proposal of
  what confirming the draft would do. Never a person's name or id.
*/
function staffView(cargo, reg, draft, crate) {
  var d = draft || reg.routes;
  var p = cargo.proposeRoutes(reg.routes, d, reg.state);
  var c = cargo.countsOf(reg);
  var holdsAt = {};
  Object.keys(reg.state.holds).sort().forEach(function (id) {
    var h = reg.state.holds[id];
    (holdsAt[h.port] = holdsAt[h.port] || []).push({ id: id, sailing: !!h.sailing });
  });
  return {
    open: true, mode: 'staff',
    base: baseOf(reg.routes),
    counts: c,
    holdKeys: HOLD_KEYS.slice(),
    inForce: { ports: reg.routes.ports.map(function (x) { return { key: x.key, name: x.name, hold: x.hold, crate: !!x.crate, ships: holdsAt[x.key] || [] }; }),
               routes: reg.routes.routes.map(function (r) { return { from: r.from, to: r.to, minutes: r.minutes, crew: r.crew.length }; }) },
    draft: { ports: d.ports.map(function (x) { return { key: x.key, name: x.name, hold: x.hold, crate: !!x.crate }; }),
             routes: d.routes.map(function (r) { return { from: r.from, to: r.to, minutes: r.minutes, crew: r.crew.length }; }) },
    changes: p.changes.slice(), strands: p.strands.slice(),
    canConfirm: p.changes.length > 0 && p.strands.length === 0,
    crate: crate ? { here: true, dockOf: portOfCrate(d, crate.desc) || null } : null
  };
}

/*
  WHAT A PERSON SEES AT A DOCK. input:
    reg       the register (routes, ships, state)
    port      the port key of the crate pressed
    viewer    { actor, profile }, the character at the crate
    charter   charterOf()'s answer for them
    pack      [{ baseId, nth, count, name }], what they carry, coin left out by the caller
    people    [{ actor, profile, name }], who a load can be for, the viewer first
    nameOf    function (party) -> the name to show, or '' when it cannot be read
    itemName  function (entry) -> the name of a piece
    now       the time
  Lines are shown only to whoever they concern: the one they are for, the one
  who loaded them, and staff (input.staff).
*/
function dockView(input) {
  var reg = input.reg, port = portOf(reg.routes, input.port);
  if (!port) { return { open: false }; }
  var me = input.viewer, max = reg.ships.MAX_LINES, now = input.now;
  var nameOf = input.nameOf || function () { return ''; };
  var itemName = input.itemName || function () { return 'Goods'; };
  var holds = [], incoming = [];
  Object.keys(reg.state.holds).sort().forEach(function (id) {
    var h = reg.state.holds[id];
    if (h.sailing) {
      if (h.sailing.to === port.key) {
        var from = portOf(reg.routes, h.sailing.from);
        incoming.push({ id: id, from: from ? from.name : h.sailing.from,
                        dueIn: Math.max(0, Math.ceil((h.sailing.arriveAt - now) / MINUTE)) });
      }
      return;
    }
    if (h.port !== port.key) { return; }
    var lines = reg.ships.aboard(reg.state, id).map(function (l) {
      var line = reg.state.holds[id].lines[String(l.line)];
      var mine = same(l.for, me), loaded = same(l.by, me);
      return {
        line: l.line, item: itemName(l.entry), count: l.entry.count,
        shown: mine || loaded || input.staff === true,
        forName: l.for ? (same(l.for, me) ? 'you' : (nameOf(l.for) || 'someone')) : 'nobody now',
        canCollect: mine && line.from !== h.port,
        canReturn: loaded && line.from === h.port
      };
    });
    var used = Object.keys(h.lines).length;
    var others = lines.filter(function (l) { return !l.shown; }).length;
    holds.push({
      id: id, used: used, max: max,
      lines: lines.filter(function (l) { return l.shown; }).map(function (l) { delete l.shown; return l; }),
      others: others,
      canLoad: input.charter.may && used < max,
      sail: input.charter.may ? reg.routes.routes.filter(function (r) { return r.from === port.key; }).map(function (r) {
        var to = portOf(reg.routes, r.to);
        return { to: r.to, name: to ? to.name : r.to, minutes: r.minutes };
      }) : []
    });
  });
  return {
    open: true, mode: 'dock',
    port: { key: port.key, name: port.name },
    holds: holds, incoming: incoming,
    charter: { may: input.charter.may, why: input.charter.why },
    pack: input.charter.may ? (input.pack || []).filter(function (p) { return !isCoin(p.baseId); }).map(function (p) {
      return { base: hex(p.baseId), nth: p.nth, count: p.count, name: p.name };
    }) : [],
    people: input.charter.may ? (input.people || []).map(function (p) {
      return { actor: hex(p.actor), name: same(p, me) ? 'Yourself' : p.name };
    }) : []
  };
}

module.exports = {
  GOLD_BASE: GOLD_BASE, HOLD_KEYS: HOLD_KEYS,
  isCoin: isCoin, baseOf: baseOf, portOfCrate: portOfCrate, voyage: voyage, nextArrival: nextArrival,
  charterOf: charterOf, parse: parse, editDraft: editDraft, staffView: staffView, dockView: dockView
};
