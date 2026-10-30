'use strict';
/*
  TRADE CARTS: THE STOP, THE ROAD AND THE RAID (#3158).

  Patrick, 22 Oct 2026, on his report page (docs/DECIDED.md):
    - people drive the carts that move goods between holds;
    - a shipment is lost only when people raid it, never by chance.

  game\trade-cargo.js is the manifest, created driven: a "port" is a cart stop
  and a "route" a road, and a cart leaves only with a driver and comes in only
  with them (pullIn). This file is what a person meets, as views and as the
  words the panel sends back. It never touches the world: the trade carts
  block of gamemode.js hands it what the server knows and does what it says,
  the way game\trade-ship-dock.js serves the ships.

  THE STOP. A cart stop is a container already in the world that staff picked
  (its reference, the stop's crate), with no new plugin, as a ship's dock is.
  E on it opens the stop panel and never the container. Staff put carts at a
  stop. Anyone loads a cart standing there, for anyone in the world.

  THE ROAD. Whoever has loaded something on a cart may drive it to a stop a
  road leads to; nothing about who drives it, where or when is decided here.
  The cart then goes with its driver: it is on the road until the driver
  presses the far stop's crate. The road's minutes, staff data, are the least
  time a loaded cart takes, so a carriage ride or a teleport does not bring it
  in sooner; walking or riding the road takes what it takes. One person drives
  one cart at a time.

  THE RAID. While a cart is on the road, anyone close to its driver, with both
  in the world, may open it from Raid cart beside the driver under Near you on
  P and take what is aboard. The manifest records who took what; whether it
  was a robbery is roleplay, the rule ships have at a dock (#511). The driver
  cannot raid their own cart. Nothing is ever lost any other way: no chance,
  no clock, no weather.

  WHAT IT NEVER DECIDES. Prices, pay and contracts: a haul on the notice
  board (#1393) pays whoever carries goods, and a cart is how a lot of them
  go. Coin is not cargo, here as on a ship.
*/

var GOLD_BASE = 15;
var MINUTE = 60 * 1000;
var KEY_RE = /^[a-z0-9][a-z0-9:_.-]{0,63}$/;
var WORD = '/cart';
/* The words game\trade-ship-dock.js editDraft uses, for a cart stop and a road. */
var WORDS = { place: 'stop', crate: 'cart stop', route: 'road' };

function copy(v) { return JSON.parse(JSON.stringify(v)); }
function whole(n) { return Number.isInteger(n) && n > 0; }
function hex(n) { return (Number(n) >>> 0).toString(16); }
function same(a, b) { return !!a && !!b && a.actor === b.actor && a.profile === b.profile; }
function isCoin(baseId) { return (Number(baseId) >>> 0) === GOLD_BASE; }

function routeOf(routes, from, to) {
  var list = (routes && routes.routes) || [];
  for (var i = 0; i < list.length; i++) {
    if (list[i].from === from && list[i].to === to) { return list[i]; }
  }
  return null;
}
function stopOf(routes, key) {
  var list = (routes && routes.ports) || [];
  for (var i = 0; i < list.length; i++) { if (list[i].key === key) { return list[i]; } }
  return null;
}
function nameOfStop(routes, key) { var s = stopOf(routes, key); return s ? s.name : key; }

/* When a cart leaves and the soonest it can come in: now, and now plus its road's minutes. */
function road(routes, from, to, now) {
  var r = routeOf(routes, from, to);
  if (!r) { throw new Error('No road leads from here to there.'); }
  if (!Number.isInteger(now) || now < 0) { throw new Error('The time cannot be verified.'); }
  return { at: now, arriveAt: now + r.minutes * MINUTE };
}

/* The cart this character is driving, or ''. */
function cartOfDriver(state, me) {
  var holds = (state && state.holds) || {};
  var ids = Object.keys(holds).sort();
  for (var i = 0; i < ids.length; i++) {
    var s = holds[ids[i]] && holds[ids[i]].sailing;
    if (s && same(s.driver, me)) { return ids[i]; }
  }
  return '';
}

/* Whether this character has loaded something still aboard this cart, which is who may drive it. */
function hasLoaded(state, id, me) {
  var h = state && state.holds && state.holds[id];
  if (!h) { return false; }
  return Object.keys(h.lines).some(function (k) { return h.lines[k].aboard > 0 && same(h.lines[k].by, me); });
}

/*
  THE PANEL'S WORDS. Sent by game\ui\thornswood-ship.js and the P panel, never
  typed (Patrick, 4 Oct: no chat commands for what people do). Answers
  { verb, ... } or { why } for anything it does not know.

    /cart close
    /cart load <cart> <base hex> <nth> <count> <for actor hex>
    /cart drive <cart> <stop>
    /cart pullin <cart>
    /cart collect <cart> <line> <count>
    /cart return <cart> <line> <count>
    /cart raid <driver actor hex>          from Near you on P
    /cart take <cart> <line> <count>       in the raid
    /cart staff
    /cart draft <edit ...>                 see trade-ship-dock.js editDraft
    /cart confirm <base>
    /cart add <stop>                       a new cart at a stop, staff only
    /cart bring <cart>                     staff bring in a cart on the road
*/
function parse(parts) {
  var p = Array.isArray(parts) ? parts.map(function (x) { return String(x); }) : [];
  var verb = String(p[1] || '').toLowerCase();
  var n = function (s) { return /^[0-9]{1,9}$/.test(String(s)) ? Number(s) : NaN; };
  var h = function (s) { return /^[0-9a-f]{1,8}$/i.test(String(s)) ? parseInt(s, 16) >>> 0 : NaN; };
  var key = function (s) { return typeof s === 'string' && KEY_RE.test(s) ? s : ''; };
  if (verb === 'close' || verb === 'staff') { return { verb: verb }; }
  if (verb === 'load') {
    var l = { verb: 'load', cart: key(p[2]), base: h(p[3]), nth: n(p[4]), count: n(p[5]), forActor: h(p[6]) };
    if (!l.cart || !whole(l.base) || !Number.isInteger(l.nth) || !whole(l.count) || !whole(l.forActor)) { return { why: 'That load cannot be read.' }; }
    return l;
  }
  if (verb === 'drive') {
    var d = { verb: 'drive', cart: key(p[2]), to: key(p[3]) };
    return d.cart && d.to ? d : { why: 'That road cannot be read.' };
  }
  if (verb === 'pullin' || verb === 'bring') {
    var b = { verb: verb, cart: key(p[2]) };
    return b.cart ? b : { why: 'Say which cart.' };
  }
  if (verb === 'collect' || verb === 'return' || verb === 'take') {
    var c = { verb: verb, cart: key(p[2]), line: n(p[3]), count: n(p[4]) };
    return c.cart && whole(c.line) && whole(c.count) ? c : { why: 'That cannot be read.' };
  }
  if (verb === 'raid') {
    var r = { verb: 'raid', driver: h(p[2]) };
    return whole(r.driver) ? r : { why: 'Say whose cart.' };
  }
  if (verb === 'draft') { return { verb: 'draft', edit: p.slice(2) }; }
  if (verb === 'confirm') { return p[2] ? { verb: 'confirm', base: String(p[2]) } : { why: 'That confirm cannot be read.' }; }
  if (verb === 'add') {
    var a = { verb: 'add', stop: key(p[2]) };
    return a.stop ? a : { why: 'Say which stop.' };
  }
  return { why: 'The cart does not know that.' };
}

/*
  WHAT A PERSON SEES AT A CART STOP. input:
    reg       the carts' register (routes, ships, state)
    stop      the stop key of the crate pressed
    viewer    { actor, profile }, the character at the crate
    staff     true for staff, who see every line
    pack      [{ baseId, nth, count, name }], what they carry, coin left out by the caller
    people    [{ actor, profile, name }], who a load can be for, the viewer first
    nameOf    function (party) -> the name to show, or '' when it cannot be read
    itemName  function (entry) -> the name of a piece
    now       the time
  Lines are shown only to whoever they concern: the one they are for, the one
  who loaded them, and staff.
*/
function stopView(input) {
  var reg = input.reg, stop = stopOf(reg.routes, input.stop);
  if (!stop) { return { open: false }; }
  var me = input.viewer, max = reg.ships.MAX_LINES, now = input.now;
  var nameOf = input.nameOf || function () { return ''; };
  var itemName = input.itemName || function () { return 'Goods'; };
  var driving = cartOfDriver(reg.state, me);
  var carts = [], incoming = [];
  Object.keys(reg.state.holds).sort().forEach(function (id) {
    var h = reg.state.holds[id];
    if (h.sailing) {
      if (h.sailing.to === stop.key) {
        var mine = same(h.sailing.driver, me);
        var left = Math.max(0, Math.ceil((h.sailing.arriveAt - now) / MINUTE));
        incoming.push({ id: id, from: nameOfStop(reg.routes, h.sailing.from), dueIn: left,
                        mine: mine, canPullIn: mine && left === 0 });
      }
      return;
    }
    if (h.port !== stop.key) { return; }
    var lines = reg.ships.aboard(reg.state, id).map(function (l) {
      var line = h.lines[String(l.line)];
      var forMe = same(l.for, me), loaded = same(l.by, me);
      return {
        line: l.line, item: itemName(l.entry), count: l.entry.count,
        shown: forMe || loaded || input.staff === true,
        forName: l.for ? (forMe ? 'you' : (nameOf(l.for) || 'someone')) : 'nobody now',
        canCollect: forMe && line.from !== h.port,
        canReturn: loaded && line.from === h.port
      };
    });
    var used = Object.keys(h.lines).length;
    var others = lines.filter(function (l) { return !l.shown; }).length;
    var mayDrive = !driving && hasLoaded(reg.state, id, me);
    carts.push({
      id: id, used: used, max: max,
      lines: lines.filter(function (l) { return l.shown; }).map(function (l) { delete l.shown; return l; }),
      others: others,
      canLoad: used < max,
      drive: mayDrive ? reg.routes.routes.filter(function (r) { return r.from === stop.key; }).map(function (r) {
        return { to: r.to, name: nameOfStop(reg.routes, r.to), minutes: r.minutes };
      }) : []
    });
  });
  return {
    open: true, mode: 'stop', kind: 'cart', word: WORD,
    stop: { key: stop.key, name: stop.name },
    carts: carts, incoming: incoming,
    driving: driving ? { id: driving, to: nameOfStop(reg.routes, reg.state.holds[driving].sailing.to) } : null,
    pack: (input.pack || []).filter(function (p) { return !isCoin(p.baseId); }).map(function (p) {
      return { base: hex(p.baseId), nth: p.nth, count: p.count, name: p.name };
    }),
    people: (input.people || []).map(function (p) {
      return { actor: hex(p.actor), name: same(p, me) ? 'Yourself' : p.name };
    })
  };
}

/*
  WHAT A RAIDER SEES: every piece aboard the cart, with no name of whom it is
  for or who loaded it. Each line can be taken.
*/
function raidView(input) {
  var reg = input.reg, h = reg.state.holds[input.cart];
  if (!h || !h.sailing) { return { open: false }; }
  var itemName = input.itemName || function () { return 'Goods'; };
  return {
    open: true, mode: 'raid', kind: 'cart', word: WORD,
    cart: input.cart, driver: input.driverName || 'somebody',
    road: { from: nameOfStop(reg.routes, h.sailing.from), to: nameOfStop(reg.routes, h.sailing.to) },
    lines: reg.ships.aboard(reg.state, input.cart).map(function (l) {
      return { line: l.line, item: itemName(l.entry), count: l.entry.count };
    })
  };
}

/* The carts on the road, for the staff panel: where from and to, how long left, and whether a driver is still named. */
function onRoad(reg, now) {
  var out = [];
  Object.keys(reg.state.holds).sort().forEach(function (id) {
    var s = reg.state.holds[id].sailing;
    if (!s) { return; }
    out.push({ id: id, from: nameOfStop(reg.routes, s.from), to: nameOfStop(reg.routes, s.to),
               dueIn: Math.max(0, Math.ceil((s.arriveAt - now) / MINUTE)), driver: !!s.driver });
  });
  return out;
}

module.exports = {
  GOLD_BASE: GOLD_BASE, WORD: WORD, WORDS: copy(WORDS),
  isCoin: isCoin, road: road, cartOfDriver: cartOfDriver, hasLoaded: hasLoaded,
  parse: parse, stopView: stopView, raidView: raidView, onRoad: onRoad
};
