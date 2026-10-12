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

var SETTLEMENT = typeof MERCHANT_SETTLEMENT !== 'undefined' ? MERCHANT_SETTLEMENT : require('./merchant-settlement');
var QUEST_TRANSFER = typeof QUEST_TRANSACTIONS !== 'undefined' ? QUEST_TRANSACTIONS : require('./quest-transactions');

function createNativeMerchantTransfer(mp) {
  return {
    available: function () {
      return !!mp && ['validateInventoryTransaction','compareAndSetInventory','getInventoryReceipt','getSavedInventoryReceipt',
        'getNpcAIState','getDescFromId','getIdFromDesc','get'].every(function (key) { return typeof mp[key] === 'function'; });
    },
    identity: function (id) {
      var ai = mp.getNpcAIState(id);
      if (!ai || !ai.isHuman || !Number.isInteger(ai.profileId) || ai.profileId <= 0) return null;
      return {desc:mp.getDescFromId(id),profileId:ai.profileId};
    },
    resolve: function (desc) { return mp.getIdFromDesc(desc); },
    inventory: function (id) { return mp.get(id, 'inventory'); },
    validate: function (snapshot) { return mp.validateInventoryTransaction(snapshot); },
    receipt: function (id) { return mp.getInventoryReceipt(id); },
    saved: function (id) { return mp.getSavedInventoryReceipt(id); },
    cas: function (id, expected, receipt, next, sequence, profile) {
      return mp.compareAndSetInventory(id, expected, receipt, next, sequence, profile);
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
  var sessionSerial = 0;
  var settlement = SETTLEMENT.createSettlement({purses:purses,transfer:transfer,world:deps.namespace || purses.namespace,log:deps.log,now:now});
  var active = true;

  function placeOf(reference) {
    return places[reference] || null;
  }

  function fail(text, view) {
    return { text: text, view: view || null };
  }

  function stockCopy(stock) { return JSON.parse(JSON.stringify(stock || [])); }
  function addStock(stock, entries, name) {
    entries.forEach(function (entry) {
      var key = SETTLEMENT.metadataKey(entry);
      var row = stock.find(function (held) {
        return held.name === name && SETTLEMENT.metadataKey(held.entry || {baseId:held.baseId,count:held.count}) === key;
      });
      if (row) {
        if (row.count + entry.count > MAX_GOLD) throw new Error('The shelf is full.');
        row.count += entry.count; row.entry = Object.assign({}, entry, {count:row.count});
      } else stock.push({baseId:entry.baseId,count:entry.count,name:name,entry:JSON.parse(JSON.stringify(entry))});
    });
    SETTLEMENT.inventory({entries:stock.map(function (row) { return row.entry || {baseId:row.baseId,count:row.count}; })});
    return stock;
  }
  function takeStock(stock, baseId, name, count) {
    var entries = [], left = count;
    for (var i = 0; i < stock.length && left > 0; i++) {
      var row = stock[i];
      if (row.baseId !== baseId || String(row.name || '').toLowerCase() !== name.toLowerCase()) continue;
      var n = Math.min(row.count, left);
      entries.push(Object.assign({}, row.entry || {baseId:row.baseId}, {count:n}));
      row.count -= n; left -= n;
      if (row.entry) row.entry.count = row.count;
    }
    if (left) throw new Error('The shelf is empty.');
    return {stock:stock.filter(function (row) { return row.count > 0; }),entries:entries};
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

  function sessionIdentity(human) {
    if (!human || !human.isHuman || !Number.isSafeInteger(human.profileId) || human.profileId<=0 ||
        typeof human.desc!=='string' || !human.desc || !Number.isSafeInteger(human.lifeGeneration) || human.lifeGeneration<0) return null;
    return JSON.stringify([human.desc,human.profileId,human.lifeGeneration]);
  }

  function questView(actorId) {
    var quests=typeof deps.quests==='function' && deps.quests();
    return quests ? quests.describe(actorId) : [];
  }

  function supplyKey(human, itemName) {
    return JSON.stringify([human.desc, human.profileId, itemName.toLowerCase()]);
  }
  function lastSupply(state, key, itemName) {
    var stamps = state.supply || {};
    // Old item-only stamps cannot be assigned to a character. Keep their
    // original window rather than resetting an unidentified completed supply.
    return Math.max(stamps[key] || 0, stamps[itemName.toLowerCase()] || 0);
  }

  function viewFor(merchantId, state, place, actorId, profileId, note) {
    var catalog = prices.catalog ? prices.catalog(place.bookHold) : [];
    var offers = [];
    for (var i = 0; i < catalog.length; i++) {
      var row = catalog[i];
      var held = (state.stock || []).find(function (entry) { return String(entry.name || '').toLowerCase() === String(row.name).toLowerCase(); });
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
    var human = settlement.available() ? transfer.identity(actorId) : null;
    var owns = human && human.desc && human.profileId === profileId;
    var at = now();
    for (var k = 0; k < offers.length; k++) {
      if (offers[k].buy == null) continue;
      var pay = offers[k].buy * SUPPLY_COUNT;
      var last = owns ? lastSupply(state, supplyKey(human, offers[k].name), offers[k].name) : 0;
      var ready = !!owns && !state.pending && state.purse >= pay && (!last || at - last >= SUPPLY_WAIT);
      supply.push({ name: offers[k].name, pay: pay, count: SUPPLY_COUNT, ready: ready });
    }
    var view = {
      open: true,
      transfer: settlement.available(),
      trader: place.name || 'Trader',
      place: place.locationName || '',
      hold: place.bookHold,
      purse: state.purse,
      offers: offers,
      supply: supply,
      quests: questView(actorId),
      note: note || (settlement.available()
        ? ''
        : 'Buying and selling wait on the native transfer. Nothing has moved.')
    };
    var session=sessions.get(profileId);
    if (session && session.actorId===actorId) view.sessionId=session.id;
    return view;
  }

  function recover() {
    if (!active) return [];
    var changed = settlement.tick(), views = [];
    sessions.forEach(function (session, profileId) {
      var reached=inReach(session.actorId,session.merchantId);
      if (!reached.ok || !authed(profileId,reached.human) || sessionIdentity(reached.human)!==session.identity) {
        sessions.delete(profileId); views.push({actorId:session.actorId,view:{open:false}}); return;
      }
      var quests=JSON.stringify(questView(session.actorId));
      if (changed.indexOf(session.merchantId) < 0 && quests===session.quests) return;
      var state = purses.read(session.merchantId), place = state && placeOf(state.reference);
      if (state && place) {
        var view=viewFor(session.merchantId,state,place,session.actorId,profileId);
        views.push({actorId:session.actorId,view:view});
      }
    });
    return views;
  }

  function sessionMerchant(profileId) {
    var session = sessions.get(Number(profileId));
    return session ? session.merchantId : 0;
  }

  function command(ctx) {
    if (!active) return fail('Trading is unavailable.');
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
      if (!token) return fail('Press E on a guild trader.');
      merchantId = parseInt(token, 16);
      if (!merchantId) return fail('That is not a guild trader.');
      var reached = inReach(actorId, merchantId);
      if (!reached.ok) return fail(reached.reason, { open: false });
      if (!authed(profileId, reached.human)) return fail('That request is not yours.');
      var identity=sessionIdentity(reached.human);
      if (!identity) return fail('This character is unavailable.', {open:false});
      var state = purses.prepare(merchantId);
      if (!state) return fail('That is not a guild trader.');
      var place = placeOf(state.reference);
      if (!place || !place.bookHold) {
        return fail('This trader has no hold price list.', { open: false });
      }
      var prior = sessions.get(profileId);
      var repeat = prior && prior.merchantId === merchantId && (now() - prior.at) < 3000;
      var opened = viewFor(merchantId, state, place, actorId, profileId);
      opened.sessionId=identity+':'+now()+':'+(++sessionSerial);
      sessions.set(profileId, { id:opened.sessionId, merchantId: merchantId, actorId:actorId, identity:identity, quests:JSON.stringify(opened.quests), at: now() });
      return {
        text: repeat ? '' : (opened.transfer
          ? ('Trading with ' + opened.trader + ' in ' + opened.place + '. Purse ' + opened.purse + '.')
          : ('The list for ' + opened.trader + ' is open. ' + opened.note)),
        view: opened
      };
    }

    merchantId = sessionMerchant(profileId);
    if (!merchantId) return fail('Press E on a guild trader.');
    if (sessions.get(profileId).actorId !== actorId) {
      sessions.delete(profileId);
      return fail('Press E on a guild trader with this character.', {open:false});
    }
    var again = inReach(actorId, merchantId);
    if (!again.ok) {
      sessions.delete(profileId);
      return fail(again.reason, { open: false });
    }
    if (!authed(profileId, again.human)) return fail('That request is not yours.');
    if (sessionIdentity(again.human)!==sessions.get(profileId).identity) {
      sessions.delete(profileId);
      return fail('Press E on a guild trader with this character.', {open:false});
    }
    if (verb === 'quest') {
      var quests = typeof deps.quests==='function' && deps.quests();
      if (!quests) return fail('Quest work is unavailable.');
      if (parts.length<4 || parts.length>5) return fail('Choose the work in the trader panel.');
      var result=quests.act(actorId,String(parts[2]),String(parts[3]),parts[4],merchantId);
      var reasons={class:'This work takes a different class.',rank:'This work takes a higher rank.',
        cooldown:'This work is still resting.',open:'You already hold this work.',gem:'Choose a gem first.',
        short:'You have not drawn enough to turn this work in.',none:'You do not hold this work.',
        unbound:'This work has no appointed place yet.',unwritten:'The work could not be committed just now.',
        unavailable:'Quest work is unavailable.'};
      var text=result.ok ? (parts[2]==='take'?'You take the work.':parts[2]==='return'?'The work is turned in.':'You give back what you drew and leave the work.') :
        reasons[result.why] || 'The work could not be changed.';
      var questState=purses.prepare(merchantId),questPlace=questState && placeOf(questState.reference);
      return fail(text,questState && questPlace ? viewFor(merchantId,questState,questPlace,actorId,profileId,text) : {open:false});
    }
    if (verb === 'buy' || verb === 'sell' || verb === 'supply') {
      return trade(actorId, profileId, merchantId, verb, parts.slice(2));
    }
    return fail('Use the trader panel to buy, sell, or turn in supplies.');
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
    var completedSupplyKey = null;
    if (verb === 'supply') {
      if (!settlement.available()) return fail('Buying and selling wait on the native transfer. Nothing was taken.', viewFor(merchantId, state, place, actorId, profileId));
      var human = transfer.identity(actorId);
      if (!human || !human.desc || human.profileId !== profileId) return fail('That request is not yours.');
      completedSupplyKey = supplyKey(human, itemName);
      var last = lastSupply(state, completedSupplyKey, itemName);
      if (last && now() - last < SUPPLY_WAIT) return fail('That supply is not due.');
    }
    if (npcBuys && state.purse < gold) return fail('The trader cannot pay.');
    if (!npcBuys && gold > 0 && world.carry(actorId, GOLD_BASE) < gold) return fail('You cannot pay.');
    if (npcBuys && world.carry(actorId, resolved.baseId) < asked.count) return fail('You are not carrying that.');
    if (!settlement.available()) {
      return fail('Buying and selling wait on the native transfer. Nothing was taken.', viewFor(merchantId, state, place, actorId, profileId));
    }
    var nextPurse = npcBuys ? state.purse - gold : state.purse + gold;
    if (nextPurse < 0 || nextPurse > MAX_GOLD) return fail('That price cannot be verified.');
    var moved;
    try {
      // Capture every trade's authenticated native character before a save
      // can publish a projection or reenter another request.
      var tradingHuman = transfer.identity(actorId);
      if (!tradingHuman || tradingHuman.profileId !== profileId) return fail('That request is not yours.');
      try {
        state = settlement.pruneSupplyHistory(merchantId, state, SUPPLY_WAIT);
      } catch (error) {
        active = false; sessions.clear(); settlement.shutdown();
        throw error;
      }
      if (!state || !active) return fail('The offer changed. Choose the trade again.');
      var currentHuman = transfer.identity(actorId);
      if (!currentHuman || currentHuman.desc !== tradingHuman.desc || currentHuman.profileId !== tradingHuman.profileId)
        return fail('That request is not yours.');
      var expected = SETTLEMENT.inventory(transfer.inventory(actorId));
      var outgoing = SETTLEMENT.takeEntries(expected, npcBuys ? resolved.baseId : GOLD_BASE, npcBuys ? asked.count : gold);
      var stock = stockCopy(state.stock), credit;
      if (npcBuys) {
        stock = addStock(stock, outgoing.entries, itemName);
        credit = gold > 0 ? [{baseId:GOLD_BASE,count:gold}] : [];
      } else {
        var picked = takeStock(stock, resolved.baseId, itemName, asked.count);
        stock = picked.stock; credit = picked.entries;
      }
      var nextSupply = JSON.parse(JSON.stringify(state.supply || {}));
      if (verb === 'supply') nextSupply[completedSupplyKey] = now();
      moved = settlement.begin({merchantId:merchantId,humanId:actorId,profileId:profileId,
        previous:state,expected:expected,debit:outgoing.inventory,credit:credit,kind:verb,
        next:{purse:nextPurse,stock:stock,supply:nextSupply}});
    } catch (error) {
      return fail(settlement.available() ? String(error.message || error) : 'Trading is unavailable. The saved transfer is retained.');
    }
    var current = purses.prepare(merchantId);
    if (!moved.done) return fail(moved.reason, viewFor(merchantId, current, place, actorId, profileId, moved.reason));
    var said = npcBuys
      ? ('Sold ' + asked.count + ' ' + itemName + ' for ' + gold + '. Purse ' + current.purse + '.')
      : ('Bought ' + asked.count + ' ' + itemName + ' for ' + gold + '. Purse ' + current.purse + '.');
    return {text:said,view:viewFor(merchantId, current, place, actorId, profileId)};
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
    acknowledgeView: function(actorId,view) {
      sessions.forEach(function(session){
        if(session.actorId===actorId && session.id===view.sessionId)session.quests=JSON.stringify(view.quests);
      });
    },
    command: command,
    activate: activate,
    recover: recover,
    nativeReady: function () { return settlement.available(); },
    withQuestInventoryMutation: function(actorId,change) {return settlement.withInventoryMutation(actorId,change);},
    questReady: function(actorId) {return settlement.canInventoryMutation(actorId);},
    shutdown: function () { active=false; sessions.clear(); settlement.shutdown(); },
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
    log:log,
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
          desc: mp.getDescFromId(id),
          lifeGeneration: ai && ai.lifeGeneration,
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
    quests: function () { return g.__thornswoodQuests; },
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
    try { mp.set(actorId, property, payload); }
    catch (e) { trading.shutdown(); log('merchant panel publication failed; controller revoked: ' + e); throw e; }
    trading.acknowledgeView(actorId,payload);
  };
  var timers=env.timers || (typeof setTimeout === 'function' && typeof clearTimeout === 'function' ? {setTimeout:setTimeout,clearTimeout:clearTimeout} : null);
  var alive=true, timer=null;
  var stop=trading.shutdown;
  trading.shutdown=function () {alive=false; if(timer!==null && timers) timers.clearTimeout(timer); stop();};
  function advance() {
    if(!alive) return;
    try { trading.recover().forEach(function (result) {if(alive) trading.push(result.actorId,result.view);}); }
    catch(error) {log('merchant recover: '+error);}
    // This checks exact save acknowledgements, never elapsed-time settlement.
    if(alive && trading.nativeReady() && timers) timer=timers.setTimeout(advance,1000);
  }
  if(trading.nativeReady()) advance();
  return trading;
}

module.exports = {
  createMerchantTrading: createMerchantTrading,
  createNativeMerchantTransfer: createNativeMerchantTransfer,
  createQuestTransactions: QUEST_TRANSFER.createQuestTransactions,
  actorIdentity: QUEST_TRANSFER.actorIdentity,
  targetIdentity: QUEST_TRANSFER.targetIdentity,
  installMerchantTrading: installMerchantTrading,
  bookHoldOf: bookHoldOf,
  guildSite: guildSite,
  GUILD_SITES: GUILD_SITES,
  BOOK_HOLD: BOOK_HOLD,
  GOLD_BASE: GOLD_BASE,
  REACH: REACH,
  SUPPLY_COUNT: SUPPLY_COUNT
};
