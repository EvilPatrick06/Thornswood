'use strict';
const apply=Reflect.apply;
const vector=v=>Array.isArray(v)&&v.length===3&&v.every(Number.isFinite);
const distance=(a,b)=>a.reduce((sum,n,i)=>sum+(n-b[i])**2,0);
const staticId=id=>Number.isInteger(id)&&id>0&&id<0xff000000;
function createQuestFishingSources(mp,input) {
 const fail=()=>{throw new Error('Quest fishing source evidence cannot be verified.');};
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
 const byId=new Map(),byDesc=new Set();
 if(!Array.isArray(input)||input.length!==3)fail();
 for(const original of input) {
  const row=JSON.parse(JSON.stringify(original));
  if(!vector(original.position)||row.itemType!=='INGR'||row.rank!=='expert'||row.returnMinutes!==60||byDesc.has(row.reference))fail();
  const id=resolve(row.reference),base=resolve(row.base),item=resolve(row.item),world=resolve(row.world);
  if(item===15||byId.has(id))fail();
  winner(base,'FLOR');winner(item,'INGR');winner(world,'WRLD');
  byId.set(id,{...row,id,baseId:base});byDesc.add(row.reference);
 }
 function source(row) {
  if(call('getDescFromId',row.id)!==row.reference||call('get',row.id,'isDisabled')!==false||
    call('get',row.id,'baseDesc')!==row.base)return false;
  const placement=winner(row.id,'REFR'),names=(placement.record.fields||[]).filter(f=>f&&f.type==='NAME');
  if(names.length!==1||!(names[0].data instanceof Uint8Array)||names[0].data.byteLength!==4)return false;
  const bytes=names[0].data,raw=Buffer.from(bytes.buffer,bytes.byteOffset,bytes.byteLength).readUInt32LE();
  if(mapped(placement,raw)!==row.baseId)return false;
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
module.exports={createQuestFishingSources};
