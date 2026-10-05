'use strict';
const assert = require('node:assert/strict');
const trading = require('../game/merchant-trading.js');

function memoryPurses(seed) {
  const states = new Map();
  for (const [id, state] of seed) states.set(id, JSON.parse(JSON.stringify(state)));
  return {
    namespace:'dev:test-ledger',
    read(id) { return this.prepare(id); },
    pendingRecords() { return Array.from(states,([merchantId,state])=>({merchantId,reference:state.reference,state:JSON.parse(JSON.stringify(state))})).filter(x=>x.state.pending); },
    compareAndCommit(id,rev,next) { if ((states.get(id).revision || 0)!==rev) return null; return this.commit(id,next); },
    prepare(id) {
      const state = states.get(id);
      return state ? JSON.parse(JSON.stringify(state)) : null;
    },
    commit(id, next) {
      const committed={...next,revision:(states.get(id).revision || 0)+1};
      states.set(id, JSON.parse(JSON.stringify(committed)));
      return JSON.parse(JSON.stringify(committed));
    }
  };
}

function worldOf(native) {
  const actors = {
    10: { pos: [0, 0, 0], cell: 'whiterun', profileId: 7, isHuman: true },
    1: { pos: [100, 0, 0], cell: 'whiterun', profileId: 0, isHuman: false },
    2: { pos: [900, 0, 0], cell: 'whiterun', profileId: 0, isHuman: false }
  };
  const inv = { 10: { 15: 40, 100: 8, 101: 2 } };
  const records = new Map();
  let live="null",saved="null";
  return {
    actors, inv, records,
    actor(id) { return actors[id] || null; },
    carry(id, baseId) { return (inv[id] && inv[id][baseId]) || 0; },
    save() { saved=live; },
    transfer: {
      available() { return native.on; },
      identity(id) { const a=actors[id]; return a && a.profileId>0 ? {desc:id.toString(16)+':Skyrim.esm',profileId:a.profileId} : null; },
      resolve(desc) { return parseInt(desc.split(':')[0],16); },
      inventory(id) { return {entries:Object.entries(inv[id]).filter(([,count])=>count>0).map(([baseId,count])=>({baseId:Number(baseId),count}))}; },
      receipt() { return live; }, saved() { return saved; },
      cas(id,expected,receipt,next,sequence,profile) {
        if (native.fail === 'throw') throw new Error('native failed');
        if (native.fail === 'refuse') return false;
        if (receipt!==live || JSON.stringify(this.inventory(id))!==JSON.stringify(expected) || profile!==actors[id].profileId) return false;
        inv[id]={}; for(const row of next.entries) inv[id][row.baseId]=(inv[id][row.baseId] || 0)+row.count;
        live=JSON.stringify({actor:id.toString(16)+':Skyrim.esm',profile,sequence});
        if (native.fail!=='stuck') saved=live;
        return true;
      }
    }
  };
}

const places = {
  '1:Skyrim.esm': { name: 'Belethor', locationName: 'Whiterun', hold: 'Whiterun', bookHold: 'whiterun' },
  '2:Skyrim.esm': { name: 'Template', locationName: 'CWGuardTemplates', hold: 'no hold', bookHold: null }
};
const prices = {
  quote(hold, item) {
    if (hold !== 'whiterun') return { buy: null, sell: null };
    const key = String(item).toLowerCase();
    if (key === 'iron ingot') return { buy: 3, sell: 5 };
    if (key === 'free salt') return { buy: 0, sell: null };
    return { buy: null, sell: null };
  },
  catalog() {
    return [
      { name: 'Iron Ingot', buy: 3, sell: 5 },
      { name: 'Free Salt', buy: 0, sell: null }
    ];
  }
};
function resolve(name) {
  const key = String(name).toLowerCase();
  if (key === 'iron ingot') return { name: 'Iron Ingot', baseId: 100 };
  if (key === 'free salt') return { name: 'Free Salt', baseId: 101 };
  if (key === 'gold') return { name: 'Gold', baseId: 15 };
  return null;
}

function service(native, purse) {
  const world = worldOf(native);
  const purses = memoryPurses([[1, {
    version: 1, reference: '1:Skyrim.esm', base: 'a:Skyrim.esm', purse: purse, stock: [], supply: {}
  }], [2, {
    version: 1, reference: '2:Skyrim.esm', base: 'b:Skyrim.esm', purse: 250, stock: []
  }]]);
  const api = trading.createMerchantTrading({
    purses, prices, transfer: world.transfer, world, places, resolve,
    isTrader: function (id) { return id === 1 || id === 2; },
    now: () => 1_700_000_000_000
  });
  return { api, world, purses };
}

function open(api) {
  return api.command({ actorId: 10, profileId: 7, parts: ['/merchant', '1'] });
}

let native = { on: true };
let box = service(native, 250);
let opened = open(box.api);
assert.equal(opened.view.open, true);
assert.equal(opened.view.purse, 250);
assert.equal(opened.view.transfer, true);
assert.equal(opened.view.offers[0].stock, 0);

let sold = box.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'sell', '2', 'Iron', 'Ingot'] });
assert.match(sold.text, /Sold 2/);
assert.equal(box.purses.prepare(1).purse, 244);
assert.equal(box.purses.prepare(1).stock[0].count, 2);
assert.equal(box.world.inv[10][100], 6);
assert.equal(box.world.inv[10][15], 46);
assert.equal(box.purses.prepare(1).purse + box.world.inv[10][15], 290);

let bought = box.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'buy', '1', 'Iron', 'Ingot'] });
assert.match(bought.text, /Bought 1/);
assert.equal(box.purses.prepare(1).purse, 249);
assert.equal(box.purses.prepare(1).stock[0].count, 1);
assert.equal(box.world.inv[10][100], 7);
assert.equal(box.world.inv[10][15], 41);
assert.equal(box.purses.prepare(1).purse + box.world.inv[10][15], 290);
assert.equal(box.world.inv[10][100] + box.purses.prepare(1).stock[0].count, 8);

box.purses.commit(1, Object.assign(box.purses.prepare(1), { purse: 0 }));
let broke = box.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'sell', '1', 'Iron', 'Ingot'] });
assert.match(broke.text, /cannot pay/);
assert.equal(box.purses.prepare(1).purse, 0);
assert.equal(box.purses.prepare(1).stock[0].count, 1);
assert.equal(box.world.inv[10][100], 7);

let bare = box.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'buy', '5', 'Iron', 'Ingot'] });
assert.match(bare.text, /empty/);
assert.equal(box.purses.prepare(1).stock[0].count, 1);

let off = service({ on: false }, 250);
open(off.api);
let blocked = off.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'sell', '1', 'Iron', 'Ingot'] });
assert.match(blocked.text, /native transfer/);
assert.equal(off.purses.prepare(1).purse, 250);
assert.equal(off.purses.prepare(1).stock.length, 0);
assert.equal(off.world.inv[10][15], 40);
assert.equal(off.world.inv[10][100], 8);
assert.equal(off.purses.prepare(1).pending || null, null);

let far = service({ on: true }, 250);
let away = far.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', '2'] });
assert.match(away.text, /not close enough/);
let stranger = far.api.command({ actorId: 10, profileId: 9, parts: ['/merchant', '1'] });
assert.match(stranger.text, /not yours/);
let join = far.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'join'] });
assert.match(join.text, /cannot join/);
let scene = far.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'scene'] });
assert.match(scene.text, /Scene quests/);
assert.equal(far.purses.prepare(1).purse, 250);

let held = service({ on: true }, 250);
open(held.api);
let none = held.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'sell', '1', 'Unknown', 'Thing'] });
assert.match(none.text, /not known/);
let noPrice = held.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'buy', '1', 'Free', 'Salt'] });
assert.match(noPrice.text, /No trader sells/);

let supply = service({ on: true }, 20);
open(supply.api);
let paid = supply.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'supply', 'Iron', 'Ingot'] });
assert.match(paid.text, /Sold 5/);
assert.equal(supply.purses.prepare(1).purse, 5);
assert.equal(supply.purses.prepare(1).stock[0].count, 5);
assert.equal(supply.world.inv[10][100], 3);
assert.equal(supply.world.inv[10][15], 55);
let again = supply.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'supply', 'Iron', 'Ingot'] });
assert.match(again.text, /not due/);
assert.equal(supply.purses.prepare(1).purse, 5);
let poor = service({ on: true }, 14);
open(poor.api);
let skipped = poor.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'supply', 'Iron', 'Ingot'] });
assert.match(skipped.text, /cannot pay/);
assert.equal(poor.purses.prepare(1).stock.length, 0);

let stuckNative = { on: true, fail: 'stuck' };
let stuck = service(stuckNative, 250);
open(stuck.api);
let waiting = stuck.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'sell', '1', 'Iron', 'Ingot'] });
assert.match(waiting.text, /waiting on the save/);
assert.equal(stuck.purses.prepare(1).purse, 250);
assert.ok(stuck.purses.prepare(1).pending);
assert.equal(stuck.world.inv[10][100], 7);
let second = stuck.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'sell', '1', 'Iron', 'Ingot'] });
assert.match(second.text, /waiting/);
assert.equal(stuck.purses.prepare(1).purse, 250);
stuck.world.save();
stuckNative.fail='';
stuck.api.recover([1]);
assert.equal(stuck.purses.prepare(1).purse, 247);
assert.equal(stuck.purses.prepare(1).stock[0].count, 1);
assert.equal(stuck.purses.prepare(1).pending, null);
stuck.api.recover([1]);
assert.equal(stuck.purses.prepare(1).purse, 247);

let fresh = service({ on: true }, 250);
open(fresh.api);
let free = fresh.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'sell', '1', 'Free', 'Salt'] });
assert.match(free.text, /Sold 1/);
assert.equal(fresh.purses.prepare(1).purse, 250);
assert.equal(fresh.purses.prepare(1).stock[0].count, 1);

const absent = trading.createNativeMerchantTransfer({});
assert.equal(absent.available(), false);
assert.equal(typeof absent.cas, 'function');

assert.equal(trading.bookHoldOf('Whiterun'), 'whiterun');
assert.equal(trading.bookHoldOf('no hold'), null);
assert.equal(trading.bookHoldOf('Solstheim'), 'ravenrock');

let ebox = service({ on: false }, 250);
let keyed = ebox.api.activate(10, 1);
assert.equal(keyed.view.open, true);
assert.match(keyed.text, /open|Trading/);
let repeat = ebox.api.activate(10, 1);
assert.equal(repeat.text, '');
assert.equal(repeat.view.open, true);
assert.equal(ebox.api.activate(10, 99), null);
let quiet = ebox.api.command({ actorId: 10, profileId: 7, parts: ['/merchant', 'e', '63'] });
assert.equal(quiet.text, '');
assert.equal(quiet.view, null);
const seen = new Set(trading.GUILD_SITES.map(function (site) { return site.bookHold; }));
for (const hold of Object.values(trading.BOOK_HOLD)) {
  assert.equal(seen.has(hold), true);
  assert.ok(trading.guildSite(hold).place);
}

console.log('PASS merchant trading quotes, stock, depletion, supply, reach and native gate');
