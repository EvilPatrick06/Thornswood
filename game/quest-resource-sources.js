'use strict';
const apply=Reflect.apply;
const vector=v=>Array.isArray(v)&&v.length===3&&v.every(Number.isFinite);
const distance=(a,b)=>a.reduce((sum,n,i)=>sum+(n-b[i])**2,0);
const staticId=id=>Number.isInteger(id)&&id>0&&id<0xff000000;
function createQuestSources(mp,input,contract) {
 const fail=()=>{throw new Error('Quest '+contract.label+' source evidence cannot be verified.');};
 const methods={};
 for(const key of ['get','getIdFromDesc','getDescFromId','lookupEspmRecordById']) {
  if(typeof mp[key]!=='function')fail();methods[key]=mp[key];
 }
 const call=(name,...args)=>apply(methods[name],mp,args);
 function resolve(desc) {
  if(typeof desc!=='string'||!desc)fail();const id=call('getIdFromDesc',desc);
  if(!staticId(id)||call('getDescFromId',id)!==desc)fail();return id;
 }
 function mapped(lookup,raw) {
  if(!staticId(raw)||typeof lookup.toGlobalRecordId!=='function')fail();
  const id=apply(lookup.toGlobalRecordId,lookup,[raw]);
  if(!staticId(id)||(raw&0xffffff)!==((id>>>24)===0xfe?id&0xfff:id&0xffffff))fail();
  return id;
 }
 function winner(id,type) {
  const lookup=call('lookupEspmRecordById',id),r=lookup&&lookup.record;
  if(!r||r.type!==type||mapped(lookup,r.id)!==id||!Number.isInteger(r.flags)||r.flags<0||r.flags>0xffffffff||
    r.flags&0x820)fail();return lookup;
 }
 function emptyPetty(lookup) {
  for(const [tag,value] of [['SOUL',0],['SLCP',1]]) {
   const fields=(lookup.record.fields||[]).filter(f=>f&&f.type===tag);
   if(fields.length!==1||!(fields[0].data instanceof Uint8Array)||fields[0].data.byteLength!==1||fields[0].data[0]!==value)fail();
  }
 }
 function produce(lookup,row) {
  const fields=(lookup.record.fields||[]).filter(f=>f&&f.type==='PFIG');
  if(fields.length!==1||!(fields[0].data instanceof Uint8Array)||fields[0].data.byteLength!==4)fail();
  const data=fields[0].data,raw=Buffer.from(data.buffer,data.byteOffset,4).readUInt32LE();
  if(mapped(lookup,raw)!==row.itemId)fail();
 }
 const byId=new Map(),byDesc=new Set();
 if(!Array.isArray(input)||input.length!==contract.count)fail();
 for(const original of input) {
  const row=JSON.parse(JSON.stringify(original));
  if(!vector(original.position)||row.itemType!==contract.itemType||row.rank!==contract.rank||row.returnMinutes!==contract.returnMinutes||byDesc.has(row.reference))fail();
  const id=resolve(row.reference),base=resolve(row.base),item=resolve(row.item),world=resolve(row.world);
  if(item===15||byId.has(id)||contract.vanillaIds&&id!==parseInt(row.reference.split(':')[0],16))fail();
  winner(base,contract.baseType);const itemRecord=winner(item,contract.itemType);winner(world,'WRLD');
  if(contract.emptyPetty)emptyPetty(itemRecord);
  byId.set(id,{...row,id,baseId:base,itemId:item,worldId:world});byDesc.add(row.reference);
 }
 function source(row) {
  const baseRecord=winner(row.baseId,contract.baseType);winner(row.worldId,'WRLD');
  if(contract.produce)produce(baseRecord,row);
  const itemRecord=winner(row.itemId,contract.itemType);
  if(contract.emptyPetty)emptyPetty(itemRecord);
  if(call('getDescFromId',row.id)!==row.reference||call('get',row.id,'isDisabled')!==false||
    call('get',row.id,'baseDesc')!==row.base)return false;
  const placement=winner(row.id,'REFR'),names=(placement.record.fields||[]).filter(f=>f&&f.type==='NAME');
  if(names.length!==1||!(names[0].data instanceof Uint8Array)||names[0].data.byteLength!==4)return false;
  const bytes=names[0].data,raw=Buffer.from(bytes.buffer,bytes.byteOffset,bytes.byteLength).readUInt32LE();
  if(mapped(placement,raw)!==row.baseId)return false;
  const transforms=(placement.record.fields||[]).filter(f=>f&&f.type==='DATA');
  if(transforms.length!==1||!(transforms[0].data instanceof Uint8Array)||transforms[0].data.byteLength!==24)return false;
  const transform=Buffer.from(transforms[0].data.buffer,transforms[0].data.byteOffset,24);
  const values=Array.from({length:6},(_,i)=>transform.readFloatLE(i*4));
  if(!values.every(Number.isFinite)||distance(values.slice(0,3),row.position)>0.01**2)return false;

  const loc=call('get',row.id,'locationalData');
  return !!loc&&loc.cellOrWorldDesc===row.world&&vector(loc.pos)&&distance(loc.pos,row.position)<=128**2;
 }
 for(const row of byId.values()) {
  if(!source(row))fail();
 }
 return Object.freeze({contains:desc=>byDesc.has(desc),verify(actor,ref) {
  try {
   const row=byId.get(ref);if(!row||!source(row))return false;
   const actorLoc=call('get',actor,'locationalData'),loc=call('get',ref,'locationalData');
   return !!actorLoc&&actorLoc.cellOrWorldDesc===row.world&&vector(actorLoc.pos)&&!!loc&&loc.cellOrWorldDesc===row.world&&vector(loc.pos)&&distance(loc.pos,row.position)<=128**2&&
    distance(actorLoc.pos,loc.pos)<=400**2;
  }catch(error){return false;}
 }});
}
function createQuestFishingSources(mp,input) {
 return createQuestSources(mp,input,{label:'fishing',count:3,baseType:'FLOR',itemType:'INGR',rank:'expert',returnMinutes:60});
}
function createQuestHarvestSources(mp,input) {
 return createQuestSources(mp,input,{label:'harvest',count:8,baseType:'ACTI',itemType:'INGR',rank:'novice',returnMinutes:10,vanillaIds:true});
}
function createQuestGeodeSources(mp,input) {
 return createQuestSources(mp,input,{label:'geode',count:6,baseType:'ACTI',itemType:'SLGM',rank:'novice',returnMinutes:30,vanillaIds:true,emptyPetty:true});
}
function createQuestLongfinSources(mp,input) {
 return createQuestSources(mp,input,{label:'longfin',count:8,baseType:'FLOR',itemType:'INGR',rank:'master',returnMinutes:240,produce:true});
}
module.exports={createQuestFishingSources,createQuestHarvestSources,createQuestGeodeSources,createQuestLongfinSources};
