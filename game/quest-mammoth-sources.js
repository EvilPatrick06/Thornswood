'use strict';
const apply=Reflect.apply;
const point=v=>Array.isArray(v)&&v.length===3&&[0,1,2].every(i=>Number.isFinite(v[i]));
const distance=(a,b)=>a.reduce((sum,n,i)=>sum+(n-b[i])**2,0);
const revision=v=>typeof v==='string'&&/^[1-9][0-9]{0,19}$/.test(v)&&(v.length<20||v<='18446744073709551615');
function createQuestMammothSources(mp,population) {
 const fail=()=>{throw new Error('Mammoth source evidence cannot be verified.');};
 const methods={};
 for(const key of ['get','getIdFromDesc','getDescFromId','lookupEspmRecordById','getNpcAIState']) {
  if(!mp||typeof mp[key]!=='function')fail();methods[key]=mp[key];
 }
 const call=(key,...args)=>apply(methods[key],mp,args),byId=new Map();
 const refs=['33fa6:Skyrim.esm','846ea:Skyrim.esm','846eb:Skyrim.esm'];
 const originalPositions=[[519.6705932617188,3950.623291015625,-5856],
  [-1923.1177978515625,3608.172119140625,-6275.24169921875],[-1810.09521484375,2847.945556640625,-6141.3271484375]];
 for(const [index,ref] of refs.entries()) {
  const matches=population&&Array.isArray(population.keep)?population.keep.filter(r=>r[0]===ref):[];
  if(matches.length!==1)fail();const row=JSON.parse(JSON.stringify(matches[0]));
  if(row[1]!=='dd641:Skyrim.esm'||row[2]!=='3c:Skyrim.esm'||!point(row[3])||distance(row[3],originalPositions[index])!==0||row[4]!==[2048,1536,1536][index]||
    row[5]!==240||row[6]!=='animal'||row[12]!=='mammoth')fail();
  const id=call('getIdFromDesc',ref);
  if(id!==parseInt(ref,16)||call('getDescFromId',id)!==ref)fail();
  byId.set(id,row);
 }
 function placement(id,row) {
  const lookup=call('lookupEspmRecordById',id),record=lookup&&lookup.record;
  if(!record||record.type!=='ACHR'||record.id!==id||!Number.isInteger(record.flags)||record.flags<0||record.flags>0xffffffff||record.flags&0x820||
    typeof lookup.toGlobalRecordId!=='function')return false;
  const fields=record.fields||[],names=fields.filter(f=>f.type==='NAME'),transforms=fields.filter(f=>f.type==='DATA');
  if(names.length!==1||transforms.length!==1||!(names[0].data instanceof Uint8Array)||names[0].data.byteLength!==4||
    !(transforms[0].data instanceof Uint8Array)||transforms[0].data.byteLength!==24)return false;
  const name=Buffer.from(names[0].data.buffer,names[0].data.byteOffset,4).readUInt32LE();
  const base=apply(lookup.toGlobalRecordId,lookup,[name]),baseLookup=call('lookupEspmRecordById',base);
  const baseRecord=baseLookup&&baseLookup.record;
  if(call('getDescFromId',base)!==row[1]||!baseRecord||baseRecord.type!=='NPC_'||
    !Number.isInteger(baseRecord.flags)||baseRecord.flags<0||baseRecord.flags>0xffffffff||baseRecord.flags&0x820||
    typeof baseLookup.toGlobalRecordId!=='function'||apply(baseLookup.toGlobalRecordId,baseLookup,[baseRecord.id])!==base)return false;
  const bytes=transforms[0].data,data=Buffer.from(bytes.buffer,bytes.byteOffset,24);
  const values=Array.from({length:6},(_,i)=>data.readFloatLE(i*4));
  return values.every(Number.isFinite)&&distance(values.slice(0,3),row[3])<=0.01**2;
 }
 for(const [id,row] of byId)if(!placement(id,row))fail();
 function read(actor,id) {
  try {
   const row=byId.get(id);if(!row||!placement(id,row)||call('getDescFromId',id)!==row[0])return null;
   const ai=JSON.parse(JSON.stringify(call('getNpcAIState',id)));
   if(!ai||ai.isHuman!==false||ai.isServerControlled!==true||ai.isDisabled===true||ai.isDead!==true||
     !Number.isInteger(ai.profileId)||ai.profileId>=0||!Number.isSafeInteger(ai.lifeGeneration)||ai.lifeGeneration<0||
     !revision(ai.runtimeLifeIdentity)||!point(ai.pos)||distance(ai.pos,row[3])>row[4]**2||
     ai.pos[0]<-2500||ai.pos[0]>1000||ai.pos[1]<2000||ai.pos[1]>4500||
     call('get',id,'baseDesc')!==row[1]||call('get',id,'worldOrCellDesc')!==row[2])return null;
   const loc=call('get',actor,'locationalData');
   if(!loc||loc.cellOrWorldDesc!==row[2]||!point(loc.pos)||distance(loc.pos,ai.pos)>400**2)return null;
   const final=call('getNpcAIState',id);
   if(!final||final.profileId!==ai.profileId||final.lifeGeneration!==ai.lifeGeneration||final.runtimeLifeIdentity!==ai.runtimeLifeIdentity||
     final.isHuman!==false||final.isServerControlled!==true||final.isDisabled===true||final.isDead!==true||
     !point(final.pos)||distance(final.pos,ai.pos)!==0)return null;
   return {ref:row[0],life:ai.lifeGeneration,body:ai.runtimeLifeIdentity};
  }catch(error){return null;}
 }
 return Object.freeze({contains:ref=>refs.includes(ref),read,verify(actor,id,expected) {
  const body=read(actor,id);return !!body&&!!expected&&body.ref===expected.ref&&body.life===expected.life&&body.body===expected.body;
 }});
}
module.exports={createQuestMammothSources};
