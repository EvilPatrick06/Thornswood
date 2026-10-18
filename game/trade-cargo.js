'use strict';
/*
  TRADE SHIPS: THE MANIFEST (#511).

  A trade ship is a hold, a container the server places at a dock, that is
  loaded at one port, is away for a voyage, and is emptied at another. This
  file is only the manifest: what is in each hold, whose pack every piece came
  out of, who it is for, and where it went. It never touches the world, a
  pack, a purse or a price. The design, its boundaries and the questions for
  Patrick are on #511 (issuecomment-6245473792).

  WHAT IT REFUSES TO DO, because a cargo worth robbing is a cargo worth making
  out of nothing (the trap #511 names):

  - A piece is written aboard only with the receipt of the debit that already
    took it out of somebody's pack. One receipt loads once.
  - A piece leaves only in two steps. begin() takes it off the hold and holds
    it as pending; finish() records the receipt of the credit that put it into
    exactly one pack or drop box. A pending piece is still counted, so a crash
    between the two steps neither loses it nor pays it twice.
  - Every change runs the audit: for every line, what was loaded equals what
    is aboard plus what is pending plus what went out. A hold never grows.
  - Coin is not cargo. Gold (base 0xF) is refused; freight is #512's rule.
  - Saved state that does not verify is refused. It never starts empty.

  WHAT IT NEVER DECIDES. Thornswood is a player-driven RP server (Patrick,
  17 Oct 2026, 10:13 PM MT): a trade ship is a tool, and the players decide
  what happens with it in the world. So nothing here says who sails, where,
  when or for how long. The ports, the routes, their leg times and the crews
  are staff data: checkRoutes() below reads and checks them, and
  proposeRoutes() lists what a change would do so staff can confirm it before
  it is kept. Who may load, and whether opening a hold is a crime, are the
  world's business, not this file's.

  Ownership of who may run a ship, contracts and freight belong to #512 (the
  Free Skyrim Trading Company). Prices, purses and trading belong to #1373.
  Nothing here calls either.
*/

var GOLD_BASE = 15;
var MAX_COUNT = 2147483647;
var MAX_LINES_DEFAULT = 24;
var MAX_STATE_BYTES = 512 * 1024;
var ID_RE = /^[a-z0-9][a-z0-9:_.-]{0,63}$/;
var HOWS = { delivered: 1, left: 1, returned: 1, taken: 1 };

function copy(v) { return JSON.parse(JSON.stringify(v)); }
function isObj(v) { return !!v && typeof v === 'object' && !Array.isArray(v); }
function count(n) { return Number.isInteger(n) && n > 0 && n <= MAX_COUNT; }
function text(s, max) { return typeof s === 'string' && s.length > 0 && s.length <= (max || 128) && s.trim() === s; }
function time(t) { return Number.isInteger(t) && t >= 0; }

/* A piece as the inventory holds it: base, count and every other field kept. */
function entryOf(e) {
  if (!isObj(e) || !Number.isInteger(e.baseId) || e.baseId <= 0 || e.baseId > 0xffffffff || !count(e.count)) {
    throw new Error('A piece of cargo cannot be verified.');
  }
  if (e.baseId === GOLD_BASE) { throw new Error('Coin is not cargo.'); }
  return copy(e);
}

function canonical(v) {
  if (Array.isArray(v)) { return v.map(canonical); }
  if (!isObj(v)) { return v; }
  var out = {};
  Object.keys(v).sort().forEach(function (k) { out[k] = canonical(v[k]); });
  return out;
}

function createTradeCargo(opts) {
  opts = opts || {};
  if (!Array.isArray(opts.ports) || opts.ports.length < 2) { throw new Error('A ship needs at least two ports.'); }
  var ports = {};
  opts.ports.forEach(function (p) {
    if (typeof p !== 'string' || !ID_RE.test(p) || ports[p]) { throw new Error('A port cannot be verified: ' + p); }
    ports[p] = true;
  });
  var routes = null;
  if (opts.routes !== undefined) {
    routes = {};
    if (!Array.isArray(opts.routes)) { throw new Error('The routes cannot be verified.'); }
    opts.routes.forEach(function (r) {
      if (!isObj(r) || !ports[r.from] || !ports[r.to] || r.from === r.to) { throw new Error('A route cannot be verified.'); }
      routes[r.from + '>' + r.to] = true;
    });
  }
  var maxLines = opts.maxLines === undefined ? MAX_LINES_DEFAULT : opts.maxLines;
  if (!Number.isInteger(maxLines) || maxLines < 1 || maxLines > 256) { throw new Error('The line limit cannot be verified.'); }

  function empty() { return { v: 1, seq: 0, holds: {}, receipts: {} }; }

  function holdOf(state, id) {
    var h = Object.prototype.hasOwnProperty.call(state.holds, id) ? state.holds[id] : null;
    if (!h) { throw new Error('No hold ' + id + '.'); }
    return h;
  }

  function useReceipt(state, receipt) {
    if (!text(receipt, 200)) { throw new Error('A receipt cannot be verified.'); }
    if (Object.prototype.hasOwnProperty.call(state.receipts, receipt)) { throw new Error('That receipt was already used.'); }
    state.receipts[receipt] = true;
  }

  /*
    The audit. Throws on the first thing that does not add up, so a caller that
    catches it can refuse the change and keep the state it had.
  */
  function audit(state) {
    if (!isObj(state) || state.v !== 1 || !Number.isInteger(state.seq) || state.seq < 0 ||
        !isObj(state.holds) || !isObj(state.receipts)) {
      throw new Error('The manifest cannot be verified.');
    }
    var seen = {}, used = {}, aboard = 0, pending = 0, out = 0;
    function receipt(r) {
      if (!text(r, 200) || used[r] || state.receipts[r] !== true) { throw new Error('A receipt does not match the manifest.'); }
      used[r] = true;
    }
    Object.keys(state.holds).forEach(function (id) {
      var h = state.holds[id];
      if (!ID_RE.test(id) || !isObj(h) || !ports[h.port] || !isObj(h.lines) || !Array.isArray(h.outs)) {
        throw new Error('Hold ' + id + ' cannot be verified.');
      }
      if (h.sailing !== null) {
        var s = h.sailing;
        if (!isObj(s) || s.from !== h.port || !ports[s.to] || s.to === s.from || !time(s.at) || !time(s.arriveAt) || s.arriveAt <= s.at) {
          throw new Error('Hold ' + id + '\'s voyage cannot be verified.');
        }
      }
      var left = {};
      var lines = Object.keys(h.lines);
      if (lines.length > maxLines) { throw new Error('Hold ' + id + ' carries more lines than it may.'); }
      lines.forEach(function (k) {
        var l = h.lines[k];
        if (!isObj(l) || String(l.seq) !== k || !Number.isInteger(l.seq) || l.seq < 1 || l.seq > state.seq || seen[l.seq] ||
            !text(l.by) || !text(l.for) || !ports[l.from] || !Number.isInteger(l.aboard) || l.aboard < 0) {
          throw new Error('A line in hold ' + id + ' cannot be verified.');
        }
        seen[l.seq] = true;
        entryOf(l.entry);
        if (l.aboard > l.entry.count) { throw new Error('A line in hold ' + id + ' grew.'); }
        receipt(l.receipt);
        left[k] = l.entry.count - l.aboard;
        aboard += l.aboard;
      });
      h.outs.forEach(function (o) {
        if (!isObj(o) || !Number.isInteger(o.seq) || o.seq < 1 || o.seq > state.seq || seen[o.seq] || !HOWS[o.how] ||
            !text(o.who) || !count(o.count) || !time(o.at) || !Object.prototype.hasOwnProperty.call(h.lines, String(o.line))) {
          throw new Error('Something that left hold ' + id + ' cannot be verified.');
        }
        seen[o.seq] = true;
        left[o.line] -= o.count;
        if (left[o.line] < 0) { throw new Error('More left hold ' + id + ' than was loaded.'); }
        if (o.receipt === null) { pending += o.count; } else { receipt(o.receipt); out += o.count; }
      });
      Object.keys(left).forEach(function (k) {
        if (left[k] !== 0) { throw new Error('Hold ' + id + ' does not add up.'); }
      });
    });
    Object.keys(state.receipts).forEach(function (r) {
      if (!used[r]) { throw new Error('A receipt is not on the manifest.'); }
    });
    return { aboard: aboard, pending: pending, out: out };
  }

  /* Every change works on a copy and replaces the state only once it audits. */
  function change(state, fn) {
    var next = copy(state);
    var result = fn(next);
    audit(next);
    Object.keys(state).forEach(function (k) { delete state[k]; });
    Object.keys(next).forEach(function (k) { state[k] = next[k]; });
    return result;
  }

  function open(state, id, port) {
    return change(state, function (s) {
      if (typeof id !== 'string' || !ID_RE.test(id)) { throw new Error('A hold needs a plain name.'); }
      if (Object.prototype.hasOwnProperty.call(s.holds, id)) { throw new Error('There is already a hold ' + id + '.'); }
      if (!ports[port]) { throw new Error('No port ' + port + '.'); }
      s.holds[id] = { port: port, sailing: null, lines: {}, outs: [] };
      return id;
    });
  }

  /*
    Loads one piece. The caller has already taken it out of a pack, and
    receipt names that debit. who is the loader, recipient who it is for.
  */
  function load(state, id, piece) {
    return change(state, function (s) {
      var h = holdOf(s, id);
      if (h.sailing) { throw new Error('The hold is at sea.'); }
      if (!isObj(piece) || !text(piece.by) || !text(piece.for)) { throw new Error('A load needs who loaded it and who it is for.'); }
      var e = entryOf(piece.entry);
      if (Object.keys(h.lines).length >= maxLines) { throw new Error('The hold is full.'); }
      useReceipt(s, piece.receipt);
      var seq = ++s.seq;
      h.lines[seq] = { seq: seq, by: piece.by, for: piece.for, from: h.port, receipt: piece.receipt, entry: e, aboard: e.count };
      return seq;
    });
  }

  function depart(state, id, to, at, arriveAt) {
    return change(state, function (s) {
      var h = holdOf(s, id);
      if (h.sailing) { throw new Error('The hold is already at sea.'); }
      if (!ports[to] || to === h.port || (routes && !routes[h.port + '>' + to])) {
        throw new Error('No voyage from ' + h.port + ' to ' + to + '.');
      }
      if (!time(at) || !time(arriveAt) || arriveAt <= at) { throw new Error('A voyage needs a time to leave and a later time to arrive.'); }
      var carrying = Object.keys(h.lines).some(function (k) { return h.lines[k].aboard > 0; });
      if (!carrying) { throw new Error('The hold is empty.'); }
      if (h.outs.some(function (o) { return o.receipt === null; })) { throw new Error('Something is still being handed out.'); }
      h.sailing = { from: h.port, to: to, at: at, arriveAt: arriveAt };
      return h.sailing;
    });
  }

  /*
    A staff tool, for narration: change a voyage that is under way, to another
    port on the list or to another time to arrive, or both. It never touches
    what is aboard. Staff routes do not bind it, because staff are the ones
    who wrote them; the port still has to be one a hold can stand at.
  */
  function amend(state, id, change_) {
    return change(state, function (s) {
      var h = holdOf(s, id);
      if (!h.sailing) { throw new Error('The hold is not at sea.'); }
      if (!isObj(change_)) { throw new Error('Say what changes.'); }
      var to = change_.to === undefined ? h.sailing.to : change_.to;
      var arriveAt = change_.arriveAt === undefined ? h.sailing.arriveAt : change_.arriveAt;
      if (!ports[to] || to === h.sailing.from) { throw new Error('No voyage from ' + h.sailing.from + ' to ' + to + '.'); }
      if (!time(arriveAt) || arriveAt <= h.sailing.at) { throw new Error('A voyage arrives after it left.'); }
      h.sailing.to = to;
      h.sailing.arriveAt = arriveAt;
      return h.sailing;
    });
  }

  /* Every hold whose voyage is over by now is docked at its destination. */
  function arrive(state, now) {
    if (!time(now)) { throw new Error('The time cannot be verified.'); }
    return change(state, function (s) {
      var landed = [];
      Object.keys(s.holds).sort().forEach(function (id) {
        var h = s.holds[id];
        if (h.sailing && h.sailing.arriveAt <= now) {
          h.port = h.sailing.to;
          h.sailing = null;
          landed.push(id);
        }
      });
      return landed;
    });
  }

  /*
    Takes count of a line off the hold and holds it as pending, then hands
    back what the caller must put into one pack or drop box. how is
    delivered (to the recipient), left (in the drop box under the
    recipient's name), returned (to the loader, at the port it was loaded
    in) or taken (by whoever opened it; when that is allowed is the
    caller's rule, not this file's).
  */
  function begin(state, id, line, n, how, who, at) {
    return change(state, function (s) {
      var h = holdOf(s, id);
      var l = Object.prototype.hasOwnProperty.call(h.lines, String(line)) ? h.lines[String(line)] : null;
      if (!l) { throw new Error('No such line in the hold.'); }
      if (!HOWS[how]) { throw new Error('Not a way for cargo to leave.'); }
      if (!text(who)) { throw new Error('Somebody has to receive it.'); }
      if (!count(n) || n > l.aboard) { throw new Error('There is not that much aboard.'); }
      if (!time(at)) { throw new Error('The time cannot be verified.'); }
      if (how !== 'taken' && h.sailing) { throw new Error('The hold is at sea.'); }
      if ((how === 'delivered' || how === 'left') && (who !== l.for || h.port === l.from)) {
        throw new Error('Only the person it is for receives it, at the far end.');
      }
      if (how === 'returned' && (who !== l.by || h.port !== l.from)) {
        throw new Error('Only the person who loaded it takes it back, where it was loaded.');
      }
      l.aboard -= n;
      var seq = ++s.seq;
      h.outs.push({ seq: seq, line: l.seq, count: n, how: how, who: who, at: at, receipt: null });
      var e = copy(l.entry);
      e.count = n;
      return { out: seq, entry: e };
    });
  }

  /* The credit happened; receipt names it. */
  function finish(state, id, out, receipt) {
    return change(state, function (s) {
      var h = holdOf(s, id);
      var o = h.outs.filter(function (x) { return x.seq === out; })[0];
      if (!o || o.receipt !== null) { throw new Error('Nothing is waiting to be handed out under that number.'); }
      useReceipt(s, receipt);
      o.receipt = receipt;
      return o.seq;
    });
  }

  /* The credit was refused for certain; the piece goes back aboard. */
  function undo(state, id, out) {
    return change(state, function (s) {
      var h = holdOf(s, id);
      var i = -1;
      h.outs.forEach(function (x, j) { if (x.seq === out && x.receipt === null) { i = j; } });
      if (i < 0) { throw new Error('Nothing is waiting to be handed out under that number.'); }
      var o = h.outs.splice(i, 1)[0];
      h.lines[String(o.line)].aboard += o.count;
      return o.seq;
    });
  }

  /* What is aboard a hold now, line by line, for a panel. */
  function aboard(state, id) {
    var h = holdOf(state, id);
    return Object.keys(h.lines).map(Number).sort(function (a, b) { return a - b; })
      .map(function (k) { return h.lines[k]; })
      .filter(function (l) { return l.aboard > 0; })
      .map(function (l) { var e = copy(l.entry); e.count = l.aboard; return { line: l.seq, for: l.for, by: l.by, entry: e }; });
  }

  function save(state) {
    audit(state);
    var out = JSON.stringify(canonical(state));
    if (Buffer.byteLength(out, 'utf8') > MAX_STATE_BYTES) { throw new Error('The manifest is too large to keep.'); }
    return out;
  }

  function load_(textIn) {
    if (typeof textIn !== 'string' || Buffer.byteLength(textIn, 'utf8') > MAX_STATE_BYTES) {
      throw new Error('The saved manifest cannot be verified.');
    }
    var s;
    try { s = JSON.parse(textIn); } catch (e) { throw new Error('The saved manifest cannot be verified.'); }
    audit(s);
    return s;
  }

  return {
    empty: empty, audit: audit, open: open, load: load, depart: depart, amend: amend, arrive: arrive,
    begin: begin, finish: finish, undo: undo, aboard: aboard, save: save, parse: load_,
    PORTS: Object.keys(ports), MAX_LINES: maxLines
  };
}

/*
  STAFF DATA: THE PORTS, ROUTES AND CREWS.

  Nothing about where ships go is written in code. Staff keep one list:

    { v: 1,
      ports:  [{ key, name, hold, world, pos: [x, y, z] }],
      routes: [{ from, to, minutes, crew: ['<ref>', ...] }] }

  A port is a place a hold can stand: its key, the name people read, the hold
  whose drop box takes what nobody collects, and where it stands. A route is
  one way between two ports with the real minutes a leg takes; the way back is
  its own row, so staff can make it longer, shorter or absent. crew is the
  references of any NPCs or special characters staff have stood up for it;
  empty is a route nobody crews. An empty list is a world with no ships.

  checkRoutes() refuses the whole list on the first thing wrong, so a bad edit
  never half applies. proposeRoutes() compares the list in force with an edit
  and says, line by line, what would change, including the holds a removed
  port or route would strand, so staff confirm it knowing that.
*/
var HOLD_KEYS = { whiterun: 1, solitude: 1, riften: 1, markarth: 1, windhelm: 1, falkreath: 1,
  morthal: 1, dawnstar: 1, winterhold: 1, ravenrock: 1 };
var REF_RE = /^[0-9a-f]{1,8}:[^:\s][^:]{0,95}$/i;
var MAX_ROUTE_MINUTES = 7 * 24 * 60;

function checkRoutes(cfg) {
  if (!isObj(cfg) || cfg.v !== 1 || !Array.isArray(cfg.ports) || !Array.isArray(cfg.routes) ||
      Object.keys(cfg).some(function (k) { return k !== 'v' && k !== 'ports' && k !== 'routes'; })) {
    throw new Error('The ship routes cannot be verified.');
  }
  var keys = {}, pairs = {};
  var ports = cfg.ports.map(function (p, i) {
    if (!isObj(p) || typeof p.key !== 'string' || !ID_RE.test(p.key) || keys[p.key] || !text(p.name, 64) ||
        !HOLD_KEYS[p.hold] || typeof p.world !== 'string' || !REF_RE.test(p.world) ||
        !Array.isArray(p.pos) || p.pos.length !== 3 || !p.pos.every(function (n) { return typeof n === 'number' && isFinite(n); })) {
      throw new Error('Port ' + (i + 1) + ' cannot be verified.');
    }
    keys[p.key] = true;
    return { key: p.key, name: p.name, hold: p.hold, world: p.world, pos: p.pos.slice() };
  });
  var routes = cfg.routes.map(function (r, i) {
    var crew = r && r.crew === undefined ? [] : r && r.crew;
    if (!isObj(r) || !keys[r.from] || !keys[r.to] || r.from === r.to || pairs[r.from + '>' + r.to] ||
        !Number.isInteger(r.minutes) || r.minutes < 1 || r.minutes > MAX_ROUTE_MINUTES ||
        !Array.isArray(crew) || crew.length > 64 ||
        !crew.every(function (c, j) { return typeof c === 'string' && REF_RE.test(c) && crew.indexOf(c) === j; })) {
      throw new Error('Route ' + (i + 1) + ' cannot be verified.');
    }
    pairs[r.from + '>' + r.to] = true;
    return { from: r.from, to: r.to, minutes: r.minutes, crew: crew.slice() };
  });
  return { v: 1, ports: ports, routes: routes };
}

/*
  What an edit would do, for staff to confirm. state is the manifest in force
  (or null), so a port or route that holds are at or sailing on is named.
*/
function proposeRoutes(current, next, state) {
  var a = checkRoutes(current), b = checkRoutes(next);
  var lines = [], strands = [];
  function byKey(list) { var o = {}; list.forEach(function (p) { o[p.key] = p; }); return o; }
  function byPair(list) { var o = {}; list.forEach(function (r) { o[r.from + '>' + r.to] = r; }); return o; }
  var pa = byKey(a.ports), pb = byKey(b.ports), ra = byPair(a.routes), rb = byPair(b.routes);
  Object.keys(pb).forEach(function (k) {
    if (!pa[k]) { lines.push('Add the port ' + pb[k].name + ' (' + k + ').'); }
    else if (JSON.stringify(pa[k]) !== JSON.stringify(pb[k])) { lines.push('Change the port ' + pb[k].name + ' (' + k + ').'); }
  });
  Object.keys(pa).forEach(function (k) { if (!pb[k]) { lines.push('Remove the port ' + pa[k].name + ' (' + k + ').'); } });
  Object.keys(rb).forEach(function (k) {
    var r = rb[k];
    if (!ra[k]) { lines.push('Add the route ' + r.from + ' to ' + r.to + ', ' + r.minutes + ' minutes.'); }
    else {
      if (ra[k].minutes !== r.minutes) { lines.push('The route ' + r.from + ' to ' + r.to + ' takes ' + r.minutes + ' minutes, not ' + ra[k].minutes + '.'); }
      if (JSON.stringify(ra[k].crew) !== JSON.stringify(r.crew)) { lines.push('The route ' + r.from + ' to ' + r.to + ' has a new crew of ' + r.crew.length + '.'); }
    }
  });
  Object.keys(ra).forEach(function (k) { if (!rb[k]) { lines.push('Remove the route ' + ra[k].from + ' to ' + ra[k].to + '.'); } });
  if (state && isObj(state.holds)) {
    Object.keys(state.holds).sort().forEach(function (id) {
      var h = state.holds[id];
      if (!pb[h.port]) { strands.push(id + ' is at ' + h.port + ', which this removes.'); }
      if (h.sailing && (!pb[h.sailing.to] || !rb[h.sailing.from + '>' + h.sailing.to])) {
        strands.push(id + ' is sailing ' + h.sailing.from + ' to ' + h.sailing.to + ', which this removes.');
      }
    });
  }
  return { changes: lines, strands: strands, next: b };
}

module.exports = { createTradeCargo: createTradeCargo, checkRoutes: checkRoutes, proposeRoutes: proposeRoutes, GOLD_BASE: GOLD_BASE, MAX_LINES_DEFAULT: MAX_LINES_DEFAULT };
