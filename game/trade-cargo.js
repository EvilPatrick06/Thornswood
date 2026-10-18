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

  WHAT IT LEAVES TO ITS CALLER, because Patrick has not decided it yet: the
  ports, the leg times, who may load, when a hold can be robbed, and what
  happens to cargo nobody claims. Those arrive as arguments.

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
      if (!ports[to] || to === h.port) { throw new Error('No voyage from ' + h.port + ' to ' + to + '.'); }
      if (!time(at) || !time(arriveAt) || arriveAt <= at) { throw new Error('A voyage needs a time to leave and a later time to arrive.'); }
      var carrying = Object.keys(h.lines).some(function (k) { return h.lines[k].aboard > 0; });
      if (!carrying) { throw new Error('The hold is empty.'); }
      if (h.outs.some(function (o) { return o.receipt === null; })) { throw new Error('Something is still being handed out.'); }
      h.sailing = { from: h.port, to: to, at: at, arriveAt: arriveAt };
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
    empty: empty, audit: audit, open: open, load: load, depart: depart, arrive: arrive,
    begin: begin, finish: finish, undo: undo, aboard: aboard, save: save, parse: load_,
    PORTS: Object.keys(ports), MAX_LINES: maxLines
  };
}

module.exports = { createTradeCargo: createTradeCargo, GOLD_BASE: GOLD_BASE, MAX_LINES_DEFAULT: MAX_LINES_DEFAULT };
