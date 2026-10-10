'use strict';
const assert=require('node:assert/strict');
const {createQuestTransactions,actorIdentity}=require('../game/quest-transactions');
const clone=x=>JSON.parse(JSON.stringify(x));
function fixture(options={}) {
  let inventory={entries:[{baseId:15,count:40},{baseId:100,count:4,name:'Keepsake',health:0.75}]};
  let record={v:1,open:{wolf:{kills:1}},cool:{}},receipt='null',saved='null',profile=7,pending=false;
  let calls=0,mode='',busy=false,runtime='10';
  const human=()=>({desc:'ff000010:Skyrim.esm',profileId:profile});
  const mp={
    getActorRuntimeIdentity:()=>runtime,
    getNpcAIState:()=>({isHuman:true,profileId:profile,lifeGeneration:0}),
    getDescFromId:()=>human().desc,getIdFromDesc:d=>d==='f:Skyrim.esm'?15:d==='ore:Skyrim.esm'?100:0,
    get:(id,key)=>{if(mode==='readback' && calls)throw Error('readback unavailable');return clone(key==='inventory'?inventory:record);},
    getInventoryReceipt:()=>receipt,getSavedInventoryReceipt:()=>saved,
    compareAndSetInventoryAndProperty(id,expected,old,next,seq,owner,change) {
      calls++;assert.equal(owner,profile);assert.equal(change.expectedLifeGeneration,0);
      assert.equal(change.expectedRuntimeIdentity,runtime);
      if(mode==='before')throw new Error('before mutation');
      if(mode==='refuse')return false;
      assert.deepEqual(expected,inventory);assert.equal(old,receipt);assert.deepEqual(change.expected,record);
      inventory=clone(next);record=clone(change.replacement);
      receipt=JSON.stringify({actor:human().desc,profile,sequence:seq});
      if(mode==='unknown' || mode==='readback'){record={other:true};throw new Error('unknown outcome');}
      if(mode==='after')throw new Error('notification failed');
      return true;
    }
  };
  const transfer=createQuestTransactions({mp,log:options.log,withInventoryMutation:(id,fn)=>{
    if(busy || pending || receipt!==saved)return {ok:false,why:'waiting'};
    busy=true;try{return fn(human(),()=>true);}finally{busy=false;}
  }});
  return {mp,transfer,record:()=>clone(record),inventory:()=>clone(inventory),receipt:()=>receipt,
    calls:()=>calls,mode:m=>mode=m,pending:b=>pending=b,profile:p=>profile=p,runtime:r=>runtime=r,save:()=>saved=receipt};
}
const next={v:1,open:{},cool:{wolf:1000}};
let f=fixture();
assert.equal(f.transfer.commit(10,f.record(),next,[{item:'f:Skyrim.esm',count:25}]).ok,true);
assert.deepEqual(f.record(),next);assert.equal(f.inventory().entries[0].count,65);
assert.equal(f.inventory().entries[1].name,'Keepsake');assert.equal(f.calls(),1);
assert.equal(f.transfer.commit(10,next,next,[]).ok,false,'an unsaved preceding commit stays fenced');
f.save();
assert.equal(f.transfer.commit(10,next,next,[{item:'ore:Skyrim.esm',count:-2}]).ok,true);
assert.equal(f.inventory().entries.find(x=>x.baseId===100).count,2);
assert.equal(f.inventory().entries.find(x=>x.baseId===100).health,0.75);
for(const mode of ['before','refuse']) {
  f=fixture();const before=f.inventory(),record=f.record();f.mode(mode);
  assert.equal(f.transfer.commit(10,record,next,[{item:'f:Skyrim.esm',count:25}]).ok,false);
  assert.deepEqual(f.inventory(),before);assert.deepEqual(f.record(),record);assert.equal(f.receipt(),'null');
}
f=fixture();f.mode('after');
assert.equal(f.transfer.commit(10,f.record(),next,[{item:'f:Skyrim.esm',count:25}]).ok,true,'live receipt establishes a committed write despite notification error');
assert.equal(f.calls(),1);assert.equal(f.inventory().entries[0].count,65);
f=fixture();f.mode('after');
assert.equal(f.transfer.commit(10,f.record(),{...next,open:{ebony:{drawn:1,gem:undefined}}},[]).ok,true,
  'native JSON readback establishes a commit when optional fields were omitted');
f=fixture();f.mode('unknown');
assert.equal(f.transfer.commit(10,f.record(),next,[]).ok,false);assert.equal(f.transfer.available(),false);
f.mode('');assert.equal(f.transfer.commit(10,f.record(),next,[]).ok,false);assert.equal(f.calls(),1);
f=fixture({log:()=>{throw Error('logger failed');}});f.mode('readback');
assert.equal(f.transfer.commit(10,f.record(),next,[]).uncertain,true);
assert.equal(f.transfer.available(),false,'revocation must precede fallible diagnostics');
f=fixture();f.pending(true);
assert.equal(f.transfer.commit(10,f.record(),next,[]).ok,false);assert.equal(f.calls(),0);
f=fixture();const original=f.inventory();
for(const changes of [[{item:'missing',count:1}],[{item:'ore:Skyrim.esm',count:-5}],[{item:'f:Skyrim.esm',count:0.5}]])
  assert.equal(f.transfer.commit(10,f.record(),next,changes).ok,false);
assert.equal(f.calls(),0);assert.deepEqual(f.inventory(),original);
const token=f.transfer.identity(10);f.profile(8);assert.notEqual(f.transfer.identity(10),token);
f.transfer.shutdown();assert.equal(f.transfer.commit(10,f.record(),next,[]).ok,false);
{
  const old=fixture(),before=old.inventory(),record=old.record();
  const replacement={toJSON(){old.runtime('11');return next;}};
  assert.equal(old.transfer.commit(10,record,replacement,[{item:'f:Skyrim.esm',count:25}]).ok,false,
    'replacement serialization cannot adopt a newer native session');
  assert.equal(old.calls(),0);assert.deepEqual(old.inventory(),before);assert.deepEqual(old.record(),record);
}
{
  let runtime='10';
  const mp={getActorRuntimeIdentity:()=>runtime,getNpcAIState:()=>({isHuman:true,profileId:7,lifeGeneration:0}),getDescFromId:()=> 'ff000010:Skyrim.esm'};
  const token=actorIdentity(mp,10);
  assert.deepEqual(JSON.parse(token),{desc:'ff000010:Skyrim.esm',profileId:7,life:0,runtime:'10'});
  runtime='11';
  assert.notEqual(actorIdentity(mp,10),token,'same human life/ownership changes cannot retain the token');
  for(const invalid of [undefined,null,0,1,'','0','01','-1','1.5',' 1','1\n','18446744073709551616']) {
    runtime=invalid;
    assert.equal(actorIdentity(mp,10),null,'unverifiable native revision refuses delayed ownership');
  }
  runtime='18446744073709551615';
  assert.notEqual(actorIdentity(mp,10),null,'uint64 revisions are not truncated by JS numbers');
  runtime='10';
  mp.getDescFromId=()=> 'ff000011:Skyrim.esm';
  assert.notEqual(actorIdentity(mp,10),token,'descriptor replacement cannot retain ownership');
  for(const ai of [null,{isHuman:false,profileId:7,lifeGeneration:0},
    {isHuman:true,profileId:0,lifeGeneration:0},{isHuman:true,profileId:7,lifeGeneration:-1},
    {isHuman:true,profileId:7,lifeGeneration:NaN},{isHuman:true,profileId:7,lifeGeneration:0.5}]) {
    mp.getNpcAIState=()=>ai;
    assert.equal(actorIdentity(mp,10),null,'unverifiable identity refuses delayed ownership');
  }
  mp.getNpcAIState=()=>{throw Error('actor unloaded');};
  assert.equal(actorIdentity(mp,10),null);
}
console.log('PASS quest atomic inventory/state, metadata, save admission, publication errors, refusal and revocation');
