'use strict';

var GOLD_BASE = 15;
var REACH = 400;
var SUPPLY_COUNT = 5;
var SUPPLY_WAIT = 6 * 60 * 60 * 1000;
var MAX_GOLD = 2147483647;
var MAX_COUNT = 100000;

var BOOK_HOLD = {
  Whiterun: 'whiterun',
  Haafingar: 'solitude',
  'the Rift': 'riften',
  'the Reach': 'markarth',
  Eastmarch: 'windhelm',
  Falkreath: 'falkreath',
  Hjaalmarch: 'morthal',
  'the Pale': 'dawnstar',
  Winterhold: 'winterhold',
  Solstheim: 'ravenrock'
};

function bookHoldOf(hold) {
  if (!hold || hold === 'no hold') return null;
  return BOOK_HOLD[hold] || null;
}

function loadGuildSites() {
  if (typeof MERCHANT_GUILD_SITES !== 'undefined') return MERCHANT_GUILD_SITES;
  var fs = require('fs');
  var path = require('path');
  var file = path.join(__dirname, 'data', 'guild-sites.json');
  var doc = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (!doc || !Array.isArray(doc.sites) || doc.sites.length !== 10) {
    throw new Error('Each hold needs one guild site.');
  }
  return doc.sites;
}

var GUILD_SITES = loadGuildSites();

function guildSite(bookHold) {
  for (var i = 0; i < GUILD_SITES.length; i++) {
    if (GUILD_SITES[i].bookHold === bookHold) return GUILD_SITES[i];
  }
  return null;
}

function createNativeMerchantTransfer(api) {
  function ready() {
    return !!api &&
      typeof api.beginMerchantTransfer === 'function' &&
      typeof api.commitMerchantHumanDebit === 'function' &&
      typeof api.isMerchantHumanDebitDurable === 'function' &&
      typeof api.releaseMerchantQuarantine === 'function';
  }
  return {
    available: ready,
    recall: function (id) {
      if (!api || typeof api.merchantTransferStatus !== 'function') return { known: false };
      var status = api.merchantTransferStatus(id);
      if (!status) return { known: false };
      return {
        known: status.known !== false,
        durable: !!status.durable,
        attempted: !!status.attempted
      };
    },
    move: function (req) {
      if (!ready()) {
        return {
          ok: false, durable: false, attempted: false,
          reason: 'Native merchant transfer is not on this server.'
        };
      }
      var began = api.beginMerchantTransfer({
        humanId: req.humanId,
        merchantId: req.merchantId,
        humanLoses: req.humanLoses,
        humanGains: req.humanGains,
        intentId: req.intentId
      });
      if (!began || !began.ok) {
        return {
          ok: false, durable: false, attempted: false,
          reason: (began && began.reason) || 'The transfer was refused.'
        };
      }
      var debit = api.commitMerchantHumanDebit(req.humanId, began.offerId);
      if (!debit || !debit.ok) {
        return {
          ok: false, durable: false, attempted: !!(debit && debit.attempted),
          offerId: began.offerId,
          reason: (debit && debit.reason) || 'The debit was refused.'
        };
      }
      if (!api.isMerchantHumanDebitDurable(req.humanId, began.offerId)) {
        return {
          ok: false, durable: false, attempted: true, offerId: began.offerId,
          reason: 'The debit is not durable yet.'
        };
      }
      var released = api.releaseMerchantQuarantine(req.humanId, began.offerId);
      if (!released || !released.ok) {
        return {
          ok: false, durable: false, attempted: true, offerId: began.offerId,
          reason: (released && released.reason) || 'Quarantine was not released.'
        };
      }
      var done = typeof api.merchantTransferStatus === 'function'
        ? api.merchantTransferStatus(began.offerId) : { known: true, durable: true, attempted: true };
      if (!done || !done.durable) {
        return {
          ok: false, durable: false, attempted: true, offerId: began.offerId,
          reason: 'The transfer is not durable yet.'
        };
      }
      return { ok: true, durable: true, attempted: true, offerId: began.offerId };
    }
  };
}

function createMerchantTrading(deps) {
  var purses = deps.purses;
  var prices = deps.prices;
  var transfer = deps.transfer;
  var world = deps.world;
  var places = deps.places || {};
  var now = deps.now || function () { return Date.now(); };
  var reach = deps.reach == null ? REACH : deps.reach;
  var sessions = new Map();
  var seq = 0;

  function placeOf(reference) {
    return places[reference] || null;
  }

  function fail(text, view) {
    return { text: text, view: view || null };
  }

  function stockCopy(stock) {
    return (stock || []).map(function (row) {
      return { baseId: row.baseId, count: row.count, name: row.name };
    });
  }

  function sameStock(a, b) {
    return JSON.stringify(stockCopy(a)) === JSON.stringify(stockCopy(b));
  }

  function findStock(stock, name, baseId) {
    var key = String(name || '').toLowerCase();
    for (var i = 0; i < stock.length; i++) {
      if (stock[i].baseId === baseId && String(stock[i].name || '').toLowerCase() === key) return stock[i];
    }
    for (var j = 0; j < stock.length; j++) {
      if (stock[j].baseId === baseId) return stock[j];
    }
    return null;
  }

  function addStock(stock, baseId, name, count) {
    var row = findStock(stock, name, baseId);
    if (row) row.count += count;
    else stock.push({ baseId: baseId, count: count, name: name });
  }

  function takeStock(stock, baseId, name, count) {
    var row = findStock(stock, name, baseId);
    if (!row || row.count < count) return false;
    row.count -= count;
    if (row.count === 0) stock.splice(stock.indexOf(row), 1);
    return true;
  }

  function inReach(humanId, merchantId) {
    var human = world.actor(humanId);
    var merchant = world.actor(merchantId);
    if (!human || !merchant || !human.pos || !merchant.pos) {
      return { ok: false, reason: 'You are not close enough to trade.' };
    }
    if (human.isHuman !== true || !(human.profileId > 0)) {
      return { ok: false, reason: 'Only a person can trade.' };
    }
    if (merchant.isHuman || merchant.profileId > 0) {
      return { ok: false, reason: 'That is not a guild trader.' };
    }
    if (String(human.cell) !== String(merchant.cell) || human.cell == null || human.cell === '') {
      return { ok: false, reason: 'You are not close enough to trade.' };
    }
    var d = Math.hypot(
      human.pos[0] - merchant.pos[0],
      human.pos[1] - merchant.pos[1],
      human.pos[2] - merchant.pos[2]
    );
    if (!(d <= reach)) return { ok: false, reason: 'You are not close enough to trade.' };
    return { ok: true, distance: d, human: human };
  }

  function authed(profileId, human) {
    return Number(profileId) > 0 && Number(profileId) === Number(human.profileId);
  }

  function viewFor(merchantId, state, place, note) {
    var catalog = prices.catalog ? prices.catalog(place.bookHold) : [];
    var offers = [];
    for (var i = 0; i < catalog.length; i++) {
      var row = catalog[i];
      var held = findStock(state.stock || [], row.name, null);
      var count = 0;
      var stock = state.stock || [];
      for (var s = 0; s < stock.length; s++) {
        if (String(stock[s].name || '').toLowerCase() === String(row.name).toLowerCase()) count += stock[s].count;
      }
      offers.push({
        name: row.name,
        buy: row.buy,
        sell: row.sell,
        stock: count,
        baseId: held ? held.baseId : null
      });
    }
    var supply = [];
    var stamp = state.supply || {};
    var at = now();
    for (var k = 0; k < offers.length; k++) {
      if (offers[k].buy == null) continue;
      var pay = offers[k].buy * SUPPLY_COUNT;
      var last = stamp[offers[k].name.toLowerCase()] || 0;
      var ready = state.purse >= pay && (!last || at - last >= SUPPLY_WAIT);
      supply.push({ name: offers[k].name, pay: pay, count: SUPPLY_COUNT, ready: ready });
    }
    return {
      open: true,
      transfer: !!(transfer && transfer.available && transfer.available()),
      trader: place.name || 'Trader',
      place: place.locationName || '',
      hold: place.bookHold,
      purse: state.purse,
      offers: offers,
      supply: supply,
      note: note || (transfer && transfer.available && transfer.available()
        ? ''
        : 'Buying and selling wait on the native transfer. Nothing has moved.')
    };
  }

  function clearPending(id, state) {
    var next = JSON.parse(JSON.stringify(state));
    next.pending = null;
    purses.commit(id, next);
    return purses.prepare(id);
  }

  function applyPending(id, state) {
    var pending = state.pending;
    if (!pending) return state;
    if (state.purse === pending.nextPurse && sameStock(state.stock, pending.nextStock)) {
      return clearPending(id, state);
    }
    if (state.purse !== pending.previousPurse || !sameStock(state.stock, pending.previousStock)) {
      return state;
    }
    var next = JSON.parse(JSON.stringify(state));
    next.purse = pending.nextPurse;
    next.stock = stockCopy(pending.nextStock);
    next.supply = pending.nextSupply || state.supply || {};
    next.pending = null;
    purses.commit(id, next);
    return purses.prepare(id);
  }

  function recoverOne(id) {
    var state = purses.prepare(id);
    if (!state || !state.pending) return;
    var recalled = { known: false };
    try {
      if (transfer && transfer.recall) recalled = transfer.recall(state.pending.id) || { known: false };
    } catch (e) {
      return;
    }
    if (recalled.durable) applyPending(id, state);
    else if (recalled.known && !recalled.attempted) clearPending(id, state);
  }

  function recover(ids) {
    for (var i = 0; i < ids.length; i++) recoverOne(ids[i]);
  }

  function sessionMerchant(profileId) {
    var session = sessions.get(Number(profileId));
    return session ? session.merchantId : 0;
  }

  function command(ctx) {
    var parts = (ctx && ctx.parts) || [];
    var profileId = Number(ctx && ctx.profileId) || 0;
    var actorId = ctx && ctx.actorId;
    var verb = String(parts[1] || '').toLowerCase();
    if (!profileId || !actorId) return fail('You are not in the world yet.');
    if (verb === 'join' || verb === 'dues' || verb === 'fee') {
      return fail('People cannot join the Merchant\'s Guild.');
    }
    if (verb === 'scene') {
      return fail('Scene quests are not paid from a trader\'s purse.');
    }
    if (verb === 'e') {
      var pressed = parseInt(String(parts[2] || ''), 16);
      if (!pressed || (typeof deps.isTrader === 'function' && !deps.isTrader(pressed))) {
        return { text: '', view: null };
      }
      return command({ actorId: actorId, profileId: profileId, parts: ['/merchant', pressed.toString(16)] });
    }
    if (verb === 'close') {
      sessions.delete(profileId);
      return { text: 'You step back from the trader.', view: { open: false } };
    }
    if (verb === 'refresh') {
      var openId = sessionMerchant(profileId);
      if (!openId) return fail('You are not at a trader.');
      return command({ actorId: actorId, profileId: profileId, parts: ['/merchant', openId.toString(16)] });
    }

    var merchantId = 0;
    if (!verb || verb === 'open' || /^[0-9a-f]+$/i.test(verb)) {
      var token = verb === 'open' ? parts[2] : (verb || '');
      if (!token) return fail('Look at a guild trader and use /merchant with their id.');
      merchantId = parseInt(token, 16);
      if (!merchantId) return fail('That is not a guild trader.');
      var reached = inReach(actorId, merchantId);
      if (!reached.ok) return fail(reached.reason, { open: false });
      if (!authed(profileId, reached.human)) return fail('That request is not yours.');
      var state = purses.prepare(merchantId);
      if (!state) return fail('That is not a guild trader.');
      var place = placeOf(state.reference);
      if (!place || !place.bookHold) {
        return fail('This trader has no hold price list.', { open: false });
      }
      var prior = sessions.get(profileId);
      var repeat = prior && prior.merchantId === merchantId && (now() - prior.at) < 3000;
      sessions.set(profileId, { merchantId: merchantId, at: now() });
      var opened = viewFor(merchantId, state, place);
      return {
        text: repeat ? '' : (opened.transfer
          ? ('Trading with ' + opened.trader + ' in ' + opened.place + '. Purse ' + opened.purse + '.')
          : ('The list for ' + opened.trader + ' is open. ' + opened.note)),
        view: opened
      };
    }

    merchantId = sessionMerchant(profileId);
    if (!merchantId) return fail('Look at a guild trader and use /merchant with their id.');
    var again = inReach(actorId, merchantId);
    if (!again.ok) {
      sessions.delete(profileId);
      return fail(again.reason, { open: false });
    }
    if (!authed(profileId, again.human)) return fail('That request is not yours.');
    if (verb === 'buy' || verb === 'sell' || verb === 'supply') {
      return trade(actorId, profileId, merchantId, verb, parts.slice(2));
    }
    return fail('merchant: look at a trader, then buy, sell, or supply. People cannot join.');
  }

  function parseCountAndName(bits, fixedCount) {
    if (fixedCount) return { count: fixedCount, name: bits.join(' ').trim() };
    if (!bits.length) return null;
    var count = Number(bits[0]);
    if (!Number.isInteger(count) || count < 1 || count > MAX_COUNT) return null;
    return { count: count, name: bits.slice(1).join(' ').trim() };
  }

  function trade(actorId, profileId, merchantId, verb, bits) {
    var state = purses.prepare(merchantId);
    if (!state) return fail('That is not a guild trader.');
    if (state.pending) return fail('This trader has a transfer waiting.');
    var place = placeOf(state.reference);
    if (!place || !place.bookHold) return fail('This trader has no hold price list.');
    var asked = parseCountAndName(bits, verb === 'supply' ? SUPPLY_COUNT : 0);
    if (!asked || !asked.name) return fail('Name the count, then the item.');
    var resolved = deps.resolve ? deps.resolve(asked.name) : null;
    if (!resolved || resolved.error || !resolved.baseId || resolved.baseId === GOLD_BASE) {
      return fail((resolved && resolved.error) || 'That item is not known.');
    }
    var itemName = resolved.name || asked.name;
    var price = prices.quote(place.bookHold, itemName) || { buy: null, sell: null };
    var unit = verb === 'buy' ? price.sell : price.buy;
    if (unit == null) {
      return fail(verb === 'buy' ? 'No trader sells that.' : 'No trader buys that.');
    }
    if (!Number.isInteger(unit) || unit < 0 || unit > MAX_GOLD) return fail('That price cannot be verified.');
    var gold = unit * asked.count;
    if (!Number.isInteger(gold) || gold < 0 || gold > MAX_GOLD) return fail('That price cannot be verified.');
    var npcBuys = verb !== 'buy';
    if (verb === 'supply') {
      var last = (state.supply && state.supply[itemName.toLowerCase()]) || 0;
      if (last && now() - last < SUPPLY_WAIT) return fail('That supply is not due.');
    }
    if (npcBuys && state.purse < gold) return fail('The trader cannot pay.');
    if (!npcBuys && gold > 0 && world.carry(actorId, GOLD_BASE) < gold) return fail('You cannot pay.');
    if (npcBuys && world.carry(actorId, resolved.baseId) < asked.count) return fail('You are not carrying that.');
    var stock = stockCopy(state.stock);
    if (!npcBuys && !takeStock(stock, resolved.baseId, itemName, asked.count)) {
      return fail('The shelf is empty.');
    }
    var nextPurse = npcBuys ? state.purse - gold : state.purse + gold;
    if (nextPurse < 0 || nextPurse > MAX_GOLD) return fail('That price cannot be verified.');
    if (npcBuys) addStock(stock, resolved.baseId, itemName, asked.count);
    var humanLoses = [];
    var humanGains = [];
    if (npcBuys) {
      humanLoses.push({ baseId: resolved.baseId, count: asked.count });
      if (gold > 0) humanGains.push({ baseId: GOLD_BASE, count: gold });
    } else {
      if (gold > 0) humanLoses.push({ baseId: GOLD_BASE, count: gold });
      humanGains.push({ baseId: resolved.baseId, count: asked.count });
    }
    if (!humanLoses.length && !humanGains.length) return fail('Nothing would move.');
    if (!transfer || !transfer.available || !transfer.available()) {
      var waiting = viewFor(merchantId, state, place);
      return fail('Buying and selling wait on the native transfer. Nothing was taken.', waiting);
    }
    seq += 1;
    var intentId = state.reference + ':' + now() + ':' + seq;
    var nextSupply = JSON.parse(JSON.stringify(state.supply || {}));
    if (verb === 'supply') nextSupply[itemName.toLowerCase()] = now();
    var pending = {
      id: intentId,
      kind: verb,
      previousPurse: state.purse,
      previousStock: stockCopy(state.stock),
      nextPurse: nextPurse,
      nextStock: stock,
      nextSupply: nextSupply
    };
    var armed = JSON.parse(JSON.stringify(state));
    armed.pending = pending;
    purses.commit(merchantId, armed);
    var moved;
    try {
      moved = transfer.move({
        humanId: actorId,
        merchantId: merchantId,
        humanLoses: humanLoses,
        humanGains: humanGains,
        intentId: intentId
      });
    } catch (e) {
      moved = { ok: false, durable: false, attempted: true, reason: 'The transfer failed.' };
    }
    var current = purses.prepare(merchantId);
    if (moved && moved.durable) {
      current = applyPending(merchantId, current);
      var done = viewFor(merchantId, current, place, '');
      var said = npcBuys
        ? ('Sold ' + asked.count + ' ' + itemName + ' for ' + gold + '. Purse ' + current.purse + '.')
        : ('Bought ' + asked.count + ' ' + itemName + ' for ' + gold + '. Purse ' + current.purse + '.');
      return { text: said, view: done };
    }
    if (!moved || !moved.attempted) {
      clearPending(merchantId, current);
      return fail((moved && moved.reason) || 'The transfer was refused.', viewFor(merchantId, purses.prepare(merchantId), place));
    }
    return fail((moved && moved.reason) || 'The transfer is waiting on the save.', viewFor(merchantId, purses.prepare(merchantId), place));
  }

  function activate(actorId, merchantId) {
    if (typeof deps.isTrader === 'function' && !deps.isTrader(merchantId)) return null;
    var human = world.actor(actorId);
    var profileId = human && Number(human.profileId) || 0;
    return command({
      actorId: actorId,
      profileId: profileId,
      parts: ['/merchant', (Number(merchantId) >>> 0).toString(16)]
    });
  }

  return {
    command: command,
    activate: activate,
    recover: recover,
    nativeReady: function () { return !!(transfer && transfer.available && transfer.available()); },
    REACH: REACH,
    SUPPLY_COUNT: SUPPLY_COUNT,
    bookHoldOf: bookHoldOf
  };
}

function installMerchantTrading(env) {
  var mp = env.mp;
  var g = env.g || globalThis;
  var log = env.log || function () {};
  var fs = require('fs');
  var path = require('path');
  var root = typeof __dirname === 'string' ? __dirname : path.dirname(__filename);
  var file = path.join(root, 'data', 'merchant-traders.json');
  var doc = env.catalog || JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  var traderIds = new Set();
  if (doc.byRef) {
    Object.keys(doc.byRef).forEach(function (ref) {
      try {
        var found = mp.getIdFromDesc(ref);
        if (found) traderIds.add(Number(found) >>> 0);
      } catch (e) {}
    });
  }
  var trading = createMerchantTrading({
    purses: env.purses,
    prices: {
      quote: function (hold, item) {
        var books = g.__thornswoodBooks;
        if (!books || typeof books.guildPrice !== 'function') return { buy: null, sell: null };
        return books.guildPrice(hold, item);
      },
      catalog: function (hold) {
        var books = g.__thornswoodBooks;
        if (!books || typeof books.catalog !== 'function') return [];
        return books.catalog(hold);
      }
    },
    transfer: createNativeMerchantTransfer(mp),
    world: {
      actor: function (id) {
        var ai = null;
        try { ai = mp.getNpcAIState(id); } catch (e) { ai = null; }
        var pos = ai && Array.isArray(ai.pos) ? ai.pos.slice(0, 3) : null;
        var cell = ai ? (ai.cellOrWorld || ai.cell || null) : null;
        try {
          var p = mp.get(id, 'pos');
          if (Array.isArray(p) && p.length >= 3 && p.slice(0, 3).every(function (n) { return Number.isFinite(n); })) {
            pos = p.slice(0, 3);
          }
        } catch (e2) {}
        try {
          var c = mp.get(id, 'worldOrCellDesc');
          if (c) cell = c;
        } catch (e3) {}
        return {
          pos: pos,
          cell: cell,
          profileId: ai && ai.profileId || 0,
          isHuman: !!(ai && ai.isHuman)
        };
      },
      carry: function (id, baseId) {
        var inv = null;
        try { inv = mp.get(id, 'inventory'); } catch (e) { return 0; }
        var entries = (inv && inv.entries) || [];
        var n = 0;
        for (var i = 0; i < entries.length; i++) {
          if (entries[i] && Number(entries[i].baseId) === Number(baseId)) n += Number(entries[i].count) || 0;
        }
        return n;
      }
    },
    places: doc.byRef || {},
    resolve: function (name) {
      var fn = g.__thornswoodResolveItem;
      if (typeof fn !== 'function') return null;
      return fn(name);
    },
    isTrader: function (id) { return traderIds.has(Number(id) >>> 0); }
  });
  var property = 'thornswoodMerchantView';
  var script = [
    '(function(){',
    '  try {',
    '    var v = ctx.value;',
    '    if (!v || typeof v !== "object") { return; }',
    '    var st = ctx.state;',
    '    if (!st) { return; }',
    '    if (st.thornswoodMerchantAt === v.at) { return; }',
    '    st.thornswoodMerchantAt = v.at;',
    '    var body = JSON.stringify(v);',
    '    var src = "(function(){try{" +',
    '      "var d=" + body + ";window.thornswoodMerchantView=d;" +',
    '      "if(window.thornswoodMerchant&&window.thornswoodMerchant.setData){window.thornswoodMerchant.setData(d);}" +',
    '      "}catch(e){}})();";',
    '    try { ctx.sp.browser.executeJavaScript(src); } catch (e) { }',
    '  } catch (e) { }',
    '})();'
  ].join('\n');
  try {
    mp.makeProperty(property, {
      isVisibleByOwner: true, isVisibleByNeighbors: false,
      updateOwner: script, updateNeighbor: ''
    });
  } catch (e) {}
  trading.push = function (actorId, view) {
    var payload = JSON.parse(JSON.stringify(view || { open: false }));
    payload.at = Date.now();
    try { mp.set(actorId, property, payload); } catch (e) { log('merchant panel: ' + e); }
  };
  try { trading.recover(Array.from(traderIds)); } catch (e) { log('merchant recover: ' + e); }
  return trading;
}

module.exports = {
  createMerchantTrading: createMerchantTrading,
  createNativeMerchantTransfer: createNativeMerchantTransfer,
  installMerchantTrading: installMerchantTrading,
  bookHoldOf: bookHoldOf,
  guildSite: guildSite,
  GUILD_SITES: GUILD_SITES,
  BOOK_HOLD: BOOK_HOLD,
  GOLD_BASE: GOLD_BASE,
  REACH: REACH,
  SUPPLY_COUNT: SUPPLY_COUNT
};
