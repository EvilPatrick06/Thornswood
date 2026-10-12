'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'test-merchant-settlement.js'),'utf8'),ctx={require,console};
vm.createContext(ctx);vm.runInContext(source.slice(0,source.indexOf('// Four large snapshots')),ctx);
const copy=x=>JSON.parse(JSON.stringify(x));
function armed(){const f=ctx.fixture(),s=f.make();s.begin(f.offer());f.save();s.shutdown();f.calls.length=0;return f;}
for(const defect of ['gold','purse','metadata','inventory','wrapper','attempt']){
 const f=armed(),state=copy(f.states.get(1)),p=state.pending;
 state.reference='2:Skyrim.esm';p.reference=state.reference;p.id='second';p.human={desc:'20',profileId:8};
 p.debitReceipt=JSON.stringify({actor:'20',profile:8,sequence:1});p.finalReceipt=JSON.stringify({actor:'20',profile:8,sequence:2});
 if(defect==='gold')p.credit[0].count=4;
 if(defect==='purse')p.next.purse=248;
 if(defect==='metadata')p.next.stock[0].entry.health=0.8;
 if(defect==='inventory')p.debit.entries[0].count=39;
 if(defect==='wrapper')p.next.stock[0].entry.count=2;
 if(defect==='attempt')p.creditAttempt={expected:copy(f.inv),replacement:{entries:[{baseId:15,count:999}]}};
 f.states.set(2,state);const before=JSON.stringify(Array.from(f.states)),s=f.make();
 assert.throws(()=>s.tick(),/verified|conserv|stock/i,'later '+defect+' corruption is rejected before any recovery');
 assert.equal(s.available(),false);assert.equal(f.calls.length,0);assert.equal(JSON.stringify(Array.from(f.states)),before);
}
{
 const f=ctx.fixture(),s=f.make(),offer=f.offer();offer.next.purse=250;offer.credit=[];
 assert.equal(s.begin(offer).accepted,true);assert.ok(f.states.get(1).pending.terms);
 assert.equal(s.canRetire(),true,'new pending work retains validated terms');
 f.save();s.tick();f.save();s.tick();assert.equal(f.inv.entries[0].count,40);assert.equal(f.states.get(1).pending,null);
}
{
 const f=ctx.fixture(),state=f.states.get(1),goods={baseId:100,count:1,name:'Tempered iron',health:0.7};
 state.stock=[{baseId:100,count:1,name:'Iron Ingot',entry:copy(goods)}];
 const offer=f.offer();offer.previous=copy(state);offer.kind='buy';offer.debit=copy(f.inv);offer.credit=[goods];
 offer.next={purse:250,stock:[],supply:{}};
 const s=f.make();assert.equal(s.begin(offer).accepted,true);f.save();s.tick();f.save();s.tick();
 assert.equal(f.inv.entries[1].count,9,'a free purchase still transfers the actual goods');assert.equal(f.inv.entries[0].count,40);
}
{
 const f=armed();delete f.states.get(1).pending.terms;const s=f.make();
 assert.equal(s.canRetire(),false,'legacy reservations must finish before activating retirement');
 s.tick();assert.equal(f.states.get(1).pending.terms,undefined,'legacy compaction gains no new bytes');
 f.save();s.tick();assert.equal(f.inv.entries[0].count,43);assert.equal(f.states.get(1).pending,null);assert.equal(s.canRetire(),true);
}
{
 const f=ctx.fixture(),goods={baseId:200,count:1,name:'x'.repeat(130000)};
 f.states.get(1).stock=[{baseId:200,count:1,name:'Rare cloth',entry:copy(goods)}];
 const offer=f.offer();offer.previous=copy(f.states.get(1));offer.kind='buy';offer.credit=[goods];
 offer.debit=copy(f.inv);offer.debit.entries[0].count=37;offer.next={purse:253,stock:[],supply:{}};
 const s=f.make();s.begin(offer);
 assert.ok(JSON.stringify(f.states.get(1).pending.terms).length<512,'retained terms stay constant-size for large metadata');
 f.save();s.tick();f.save();s.tick();assert.equal(f.inv.entries.at(-1).name,goods.name);
 assert.equal(f.states.get(1).pending,null);
}
{
 const f=armed(),state=f.states.get(1),p=state.pending;
 delete p.terms;
 const held={baseId:200,count:1,name:'Old stock',entry:{baseId:200,count:1,name:''}};
 state.stock=[copy(held)];p.previous.stock=[copy(held)];p.next.stock.unshift(copy(held));
 function recovery(){
  const next={...copy(state),...copy(p.next)};next.pending.phase='credit';next.pending.previous={supply:{}};
  delete next.pending.expected;delete next.pending.debit;delete next.pending.expectedReceipt;return next;
 }
 const oldLimit=512*1024-2*128*1024-64,emptyBytes=Buffer.byteLength(JSON.stringify(recovery()));
 const padding='x'.repeat(Math.floor((oldLimit-emptyBytes)/2));
 state.stock[0].entry.name=padding;p.previous.stock[0].entry.name=padding;p.next.stock[0].entry.name=padding;
 assert.ok(Buffer.byteLength(JSON.stringify(recovery()))<=oldLimit);
 const s=f.make();s.tick();assert.equal(f.states.get(1).pending.terms,undefined,'legacy byte reservations gain no summary');
 f.save();s.tick();assert.equal(f.inv.entries[0].count,43);assert.equal(f.states.get(1).pending,null);
}
{
 const f=ctx.fixture(),state=f.states.get(1);state.supply=[1];const before=JSON.stringify(state),s=f.make();
 assert.throws(()=>s.pruneSupplyHistory(1,copy(state),1),/verified/);
 assert.equal(JSON.stringify(f.states.get(1)),before,'supply cleanup also rejects malformed current state before writes');
}
{
 const f=armed(),s=f.make();f.transfer.validate=()=>{s.shutdown();return true;};
 const before=JSON.stringify(Array.from(f.states));assert.throws(()=>s.tick(),/verified|unavailable/);
 assert.equal(f.calls.length,0);assert.equal(JSON.stringify(Array.from(f.states)),before);
}
for(const defect of ['foreign','same-owner','unchanged','sell-change']) {
 const f=ctx.fixture(),own='["10",7,"iron ingot"]',foreign=defect==='same-owner'?'["10",7,"silver ingot"]':'["20",8,"silver ingot"]';
 f.states.get(1).supply={[foreign]:1};
 const offer=f.offer();offer.next.supply={[foreign]:1};
 if(defect!=='sell-change'){offer.kind='supply';offer.next.supply[own]=100;}
 const s=f.make();s.begin(offer);f.save();s.tick();f.save();s.shutdown();
 const state=f.states.get(1);assert.equal(state.pending.phase,'credit');
 if(defect==='foreign' || defect==='same-owner')state.pending.previous.supply={[own]:100};
 if(defect==='unchanged')state.pending.previous.supply=copy(state.pending.next.supply);
 if(defect==='sell-change')state.pending.previous.supply={};
 const before=JSON.stringify(state),reloaded=f.make();f.calls.length=0;
 assert.throws(()=>reloaded.canRetire(),/verified/i,'compact '+defect+' cooldown must fail readiness');
 assert.equal(reloaded.available(),false);assert.equal(JSON.stringify(f.states.get(1)),before);assert.equal(f.calls.length,0);
}
{
 const f=ctx.fixture(),enumerate=f.purses.pendingRecords;let reads=0,s;
 f.purses.pendingRecords=()=>{const all=enumerate();if(++reads===2)s.shutdown();return all;};s=f.make();
 assert.throws(()=>s.canRetire(),/changed/,'shutdown during final enumeration cannot report readiness');
 assert.equal(s.available(),false);
}
console.log('PASS merchant saved-transfer conservation, zero prices, metadata and legacy retirement gate');
