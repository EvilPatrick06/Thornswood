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
  const live=new Map(),saved=new Map();
  return {
    actors, inv, records,
    actor(id) { return actors[id] ? {desc:id.toString(16)+':Skyrim.esm',lifeGeneration:0,runtimeIdentity:'100',...actors[id]} : null; },
    carry(id, baseId) { return (inv[id] && inv[id][baseId]) || 0; },
    save() { for (const [id,receipt] of live) saved.set(id,receipt); },
    transfer: {
      available() { return native.on; }, validate() {return true;},
      identity(id) { const a=actors[id]; return a && a.profileId>0 ? {desc:id.toString(16)+':Skyrim.esm',profileId:a.profileId} : null; },
      resolve(desc) { return parseInt(desc.split(':')[0],16); },
      inventory(id) { return {entries:Object.entries(inv[id]).filter(([,count])=>count>0).map(([baseId,count])=>({baseId:Number(baseId),count}))}; },
      receipt(id) { return live.get(id) || "null"; }, saved(id) { return saved.get(id) || "null"; },
      cas(id,expected,receipt,next,sequence,profile) {
        if (native.fail === 'throw') throw new Error('native failed');
        if (native.fail === 'refuse') return false;
        if (receipt!==(live.get(id) || "null") || JSON.stringify(this.inventory(id))!==JSON.stringify(expected) || profile!==actors[id].profileId) return false;
        inv[id]={}; for(const row of next.entries) inv[id][row.baseId]=(inv[id][row.baseId] || 0)+row.count;
        live.set(id,JSON.stringify({actor:id.toString(16)+':Skyrim.esm',profile,sequence}));
        if (native.fail!=='stuck') saved.set(id,live.get(id));
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

function service(native, purse, clock) {
  const world = worldOf(native);
  const purses = memoryPurses([[1, {
    version: 1, reference: '1:Skyrim.esm', base: 'a:Skyrim.esm', purse: purse, stock: [], supply: {}
  }], [2, {
    version: 1, reference: '2:Skyrim.esm', base: 'b:Skyrim.esm', purse: 250, stock: []
  }]]);
  const deps = {
    purses, prices, transfer: world.transfer, world, places, resolve,
    isTrader: function (id) { return id === 1 || id === 2; },
    now: clock || (() => 1_700_000_000_000)
  };
  const api = trading.createMerchantTrading(deps);
  return { api, world, purses, deps };
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
const questCalls=[];
box.deps.quests=()=>({describe:()=>[{id:'ebony',name:'The ebony'}],
  capture:()=>({owner:'held-session'}),
  act:(...args)=>{questCalls.push(args);return {ok:true};}});
assert.equal(open(box.api).view.quests[0].id,'ebony');
assert.equal(box.api.command({actorId:10,profileId:9,parts:['/merchant','quest','take','ebony']}).view,null);
assert.equal(questCalls.length,0,'forged quest profile cannot reach the controller');
box.world.actors[11]={...box.world.actors[10]};
box.api.command({actorId:11,profileId:7,parts:['/merchant','quest','take','ebony']});
assert.equal(questCalls.length,0,'a replacement actor cannot reuse the old session');
open(box.api);
box.api.command({actorId:10,profileId:7,parts:['/merchant','quest','take','gem','Ruby']});
assert.deepEqual(questCalls.pop(),[10,'take','gem','Ruby',1,{owner:'held-session'}]);
box.world.actors[10].lifeGeneration=1;
box.api.command({actorId:10,profileId:7,parts:['/merchant','quest','take','ebony']});
assert.equal(questCalls.length,0,'an earlier life cannot reuse a merchant session');
open(box.api);
box.world.actors[10].runtimeIdentity='101';
box.api.command({actorId:10,profileId:7,parts:['/merchant','quest','take','ebony']});
assert.equal(questCalls.length,0,'a new native session cannot reuse an old merchant panel');
open(box.api);
box.world.actors[10].desc='new:Skyrim.esm';
box.api.command({actorId:10,profileId:7,parts:['/merchant','quest','take','ebony']});
assert.equal(questCalls.length,0,'a changed descriptor cannot reuse a merchant session');
open(box.api);
box.world.actors[10].pos=[900,0,0];
box.api.command({actorId:10,profileId:7,parts:['/merchant','quest','take','ebony']});
assert.equal(questCalls.length,0,'out-of-reach quest action cannot reach the controller');
box.world.actors[10].pos=[0,0,0];open(box.api);
{
  const actor=box.world.actor;
  box.world.actor=function(id) {
    if(id===1)box.world.actors[10].runtimeIdentity='102';
    return actor(id);
  };
  box.api.command({actorId:10,profileId:7,parts:['/merchant','quest','abandon','ebony']});
  assert.equal(questCalls.length,0,'a merchant location callback cannot redirect an old panel into a replacement session');
  box.world.actor=actor;
  open(box.api);
}

const cooldownPanel=service({on:true},250);
let cooling=true;
cooldownPanel.deps.quests=()=>({describe:()=>[{id:'ebony',state:cooling?'cooldown':'available',canTake:!cooling}]});
open(cooldownPanel.api);
assert.equal(cooldownPanel.api.recover().length,0,'unchanged quest data does not republish');
cooling=false;
const refreshedWork=cooldownPanel.api.recover();
assert.equal(refreshedWork.length,1,'cooldown expiry updates an open panel without a trade');
assert.equal(refreshedWork[0].view.quests[0].canTake,true);
assert.equal(cooldownPanel.api.recover().length,1,'an unacknowledged publication is not cached as delivered');
cooldownPanel.api.acknowledgeView(10,refreshedWork[0].view);
assert.equal(cooldownPanel.api.recover().length,0,'a refreshed quest is not sent repeatedly');
let takenWork=false;
cooldownPanel.deps.quests=()=>({describe:()=>[{id:'ebony',state:takenWork?'open':'available'}],
  capture:()=>({owner:'held-session'}),
  act:()=>{takenWork=true;return {ok:true};}});
open(cooldownPanel.api);
const takenView=cooldownPanel.api.command({actorId:10,profileId:7,parts:['/merchant','quest','take','ebony']}).view;
assert.equal(takenView.note,'You take the work.');
cooldownPanel.api.acknowledgeView(10,takenView);
assert.equal(cooldownPanel.api.recover().length,0,'unchanged recovery retains the action feedback without replacing the view');
cooldownPanel.world.actors[10].lifeGeneration=1;
assert.deepEqual(cooldownPanel.api.recover()[0].view,{open:false},'recovery closes an obsolete character session');

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
// Supplies belong to the authenticated character, not everybody at a trader.
let supplyAt = 1_700_000_000_000;
const personal = service({on:true}, 250, () => supplyAt);
open(personal.api);
assert.match(personal.api.command({actorId:10,profileId:7,parts:['/merchant','supply','Iron','Ingot']}).text,/Sold 5/);
personal.world.actors[11]={pos:[0,0,0],cell:'whiterun',profileId:8,isHuman:true};
personal.world.inv[11]={15:40,100:8};
let secondCharacter=personal.api.command({actorId:11,profileId:8,parts:['/merchant','1']});
assert.equal(secondCharacter.view.supply[0].ready,true,'another character must have an independent supply offer');
assert.match(personal.api.command({actorId:11,profileId:8,parts:['/merchant','supply','Iron','Ingot']}).text,/Sold 5/);
// Another character on the same account also has its own cooldown.
personal.world.actors[12]={pos:[0,0,0],cell:'whiterun',profileId:7,isHuman:true};
personal.world.inv[12]={15:40,100:8};
assert.equal(personal.api.command({actorId:12,profileId:7,parts:['/merchant','1']}).view.supply[0].ready,true);
assert.match(personal.api.command({actorId:12,profileId:7,parts:['/merchant','supply','Iron','Ingot']}).text,/Sold 5/);
personal.api.shutdown();
const resumed=trading.createMerchantTrading(personal.deps);
personal.world.inv[10][100]=8;
assert.equal(open(resumed).view.supply[0].ready,false,'restart must retain this character cooldown');
assert.match(resumed.command({actorId:10,profileId:7,parts:['/merchant','supply','Iron','Ingot']}).text,/not due/);
supplyAt += 6*60*60*1000-1;
assert.equal(open(resumed).view.supply[0].ready,false);
supplyAt++;
assert.equal(open(resumed).view.supply[0].ready,true);
assert.match(resumed.command({actorId:10,profileId:7,parts:['/merchant','supply','Iron','Ingot']}).text,/Sold 5/);
assert.equal(personal.purses.prepare(1).purse,190);
assert.equal(personal.purses.prepare(1).stock[0].count,20);
assert.equal(personal.world.inv[10][15],70);
assert.equal(personal.world.inv[11][15],55);
assert.equal(personal.world.inv[12][15],55);

// A delayed or interrupted supply starts its window only at completion.
let completionAt=1_700_000_000_000;
const delayedNative={on:true,fail:'stuck'};
const delayed=service(delayedNative,250,()=>completionAt);
open(delayed.api);
assert.match(delayed.api.command({actorId:10,profileId:7,parts:['/merchant','supply','Iron','Ingot']}).text,/waiting on the save/);
assert.equal(open(delayed.api).view.supply[0].ready,false,'a pending supply is unavailable in the panel');
completionAt+=12*60*60*1000;
delayed.api.shutdown();
const delayedResume=trading.createMerchantTrading(delayed.deps);
delayed.world.save();
delete delayedNative.fail;
delayedResume.recover();
delayed.world.inv[10][100]=8;
assert.equal(open(delayedResume).view.supply[0].ready,false,'six hours start at saved completion after a long disconnect');
completionAt+=6*60*60*1000;
assert.equal(open(delayedResume).view.supply[0].ready,true);

// Expired history cannot permanently fill an otherwise empty merchant intent.
const history=service({on:true},250);
const state=history.purses.prepare(1);
for(let i=0;i<6000;i++)state.supply[JSON.stringify(['old'+i+':Skyrim.esm',i+1,'iron ingot'])]=1;
history.purses.commit(1,state);
open(history.api);
assert.match(history.api.command({actorId:10,profileId:7,parts:['/merchant','sell','1','Iron','Ingot']}).text,/Sold 1/);
assert.deepEqual(history.purses.prepare(1).supply,{});

const cleanupFailure=service({on:true},250);
let expired=cleanupFailure.purses.prepare(1);expired.supply={'old':1};cleanupFailure.purses.commit(1,expired);
cleanupFailure.purses.compareAndCommit=()=>{throw new Error('cleanup acknowledgement failed');};
open(cleanupFailure.api);
assert.match(cleanupFailure.api.command({actorId:10,profileId:7,parts:['/merchant','sell','1','Iron','Ingot']}).text,/unavailable/);
assert.equal(cleanupFailure.api.nativeReady(),false);
assert.equal(cleanupFailure.world.inv[10][100],8);
assert.equal(cleanupFailure.world.inv[10][15],40);

// A reentrant projection must not reuse the earlier character's cooldown key.
const replacedCharacter=service({on:true},250);
expired=replacedCharacter.purses.prepare(1);expired.supply={'old':1};replacedCharacter.purses.commit(1,expired);
const commitCleanup=replacedCharacter.purses.compareAndCommit.bind(replacedCharacter.purses);
replacedCharacter.purses.compareAndCommit=(...args)=>{
  const result=commitCleanup(...args);
  replacedCharacter.world.transfer.identity=()=>({desc:'new-character:Skyrim.esm',profileId:7});
  return result;
};
open(replacedCharacter.api);
assert.match(replacedCharacter.api.command({actorId:10,profileId:7,parts:['/merchant','supply','Iron','Ingot']}).text,/not yours/);
assert.equal(replacedCharacter.world.inv[10][100],8);
assert.equal(replacedCharacter.purses.prepare(1).purse,250);
assert.equal(replacedCharacter.purses.prepare(1).pending,undefined);
replacedCharacter.world.transfer.identity=(id)=>({desc:id.toString(16)+':Skyrim.esm',profileId:7});
expired=replacedCharacter.purses.prepare(1);expired.supply={'old':1};replacedCharacter.purses.commit(1,expired);
assert.match(replacedCharacter.api.command({actorId:10,profileId:7,parts:['/merchant','sell','1','Iron','Ingot']}).text,/not yours/);
assert.equal(replacedCharacter.world.inv[10][100],8);
assert.equal(replacedCharacter.purses.prepare(1).purse,250);

const reentrantCleanup=service({on:true},250);
expired=reentrantCleanup.purses.prepare(1);expired.supply={'old':1};reentrantCleanup.purses.commit(1,expired);
open(reentrantCleanup.api);
const fencedCommit=reentrantCleanup.purses.compareAndCommit.bind(reentrantCleanup.purses);
let nestedCleanup=null;
reentrantCleanup.purses.compareAndCommit=(...args)=>{
  if(!nestedCleanup)nestedCleanup=reentrantCleanup.api.command({actorId:10,profileId:7,parts:['/merchant','sell','1','Iron','Ingot']});
  return fencedCommit(...args);
};
assert.match(reentrantCleanup.api.command({actorId:10,profileId:7,parts:['/merchant','sell','1','Iron','Ingot']}).text,/Sold 1/);
assert.match(nestedCleanup.text,/offer changed/);
assert.equal(reentrantCleanup.world.inv[10][100],7);
assert.equal(reentrantCleanup.purses.prepare(1).stock[0].count,1);


// Unidentified old completions retain their window. Old pending supplies
// finish under their original key without attributing them to somebody new.
let legacyAt=1_700_000_000_000;
const legacyNative={on:true,fail:'stuck'};
const legacy=service(legacyNative,250,()=>legacyAt);
open(legacy.api);
legacy.api.command({actorId:10,profileId:7,parts:['/merchant','supply','Iron','Ingot']});
let oldPending=legacy.purses.prepare(1);
oldPending.pending.next.supply={'iron ingot':legacyAt};
legacy.purses.commit(1,oldPending);
legacyAt+=12*60*60*1000;
legacy.world.save();delete legacyNative.fail;
legacy.api.recover();
assert.equal(legacy.purses.prepare(1).pending,null);
assert.deepEqual(legacy.purses.prepare(1).supply,{'iron ingot':legacyAt});
assert.equal(open(legacy.api).view.supply[0].ready,false);
legacyAt+=6*60*60*1000;
assert.equal(open(legacy.api).view.supply[0].ready,true);

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
