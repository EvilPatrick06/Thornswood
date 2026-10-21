'use strict';
const rows=require('../game/data/merchant-retrievals.json').sources;
const evidence=require('./fixtures/merchant-retrieval-records.json');
module.exports=function fixture() {
 const plugins=require('../game/data/npc-population.json').loadOrder.map(r=>r.name);
 const descs=new Map(),records=new Map(),objects=new Map();
 function id(desc) {
  const [hex,plugin]=desc.split(':'),index=plugins.indexOf(plugin);
  if(index<0)throw new Error('Unknown fixture plugin: '+plugin);
  const value=(index*0x1000000+parseInt(hex,16))>>>0;descs.set(value,desc);return value;
 }
 const record=(desc,type,fields=[])=>{
  const n=id(desc);records.set(n,{record:{id:n,type,flags:0,fields},toGlobalRecordId:raw=>raw});return n;
 };
 for(const row of rows) {
  record(row.base,row.baseType);record(row.world,row.spaceType);
  record(row.item,'MISC',[{type:'DATA',data:Buffer.alloc(8)}]);
  const saved=evidence.find(r=>r.reference===row.reference),[type,rawId,flags,fields]=saved.record;
  const masters=saved.masters.concat(row.provenance.plugin);
  records.set(id(row.reference),{record:{type,id:rawId,flags,fields:fields.map(([type,hex])=>({type,data:Buffer.from(hex,'hex')}))},
   fileIndex:row.provenance.fileIndex,toGlobalRecordId:raw=>id((raw&0xffffff).toString(16)+':'+masters[raw>>>24])});
  objects.set(id(row.reference),{baseDesc:row.base,isDisabled:false,locationalData:{cellOrWorldDesc:row.world,pos:row.position.slice()}});
 }
 objects.set(10,{locationalData:{cellOrWorldDesc:rows[0].world,pos:rows[0].position.slice()}});
 return {id,records,objects,mp:{getIdFromDesc:id,getDescFromId:n=>descs.get(n),lookupEspmRecordById:n=>records.get(n),get:(n,key)=>objects.get(n)?.[key]}};
};
