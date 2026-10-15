'use strict';
// Bind an already isolated native reader. This creates no server or actors.
const apply=Reflect.apply;
function fail() {throw new Error('Native merchant ledger evidence cannot be verified.');}
function staticId(id) {return Number.isInteger(id) && id>0 && id<0xff000000;}
function createLedgerNativeValidators(mp) {
  const methods={};
  try {
    for(const key of ['getIdFromDesc','getDescFromId','lookupEspmRecordById','validateInventoryTransaction']) {
      const method=mp[key];
      if(typeof method!=='function')fail();
      methods[key]=method;
    }
  } catch(error) {fail();}
  const call=(key,...args)=>apply(methods[key],mp,args);
  function resolve(description) {
    if(typeof description!=='string' || !description)fail();
    const id=call('getIdFromDesc',description);
    if(!staticId(id) || call('getDescFromId',id)!==description)fail();
    return id;
  }
  function mapped(lookup,raw) {
    if(!staticId(raw) || typeof lookup.toGlobalRecordId!=='function')fail();
    const id=apply(lookup.toGlobalRecordId,lookup,[raw]);
    if(!staticId(id))fail();
    // Native light-slot mapping masks high local bits instead of rejecting them.
    const local=(id>>>24)===0xfe?id&0xfff:id&0xffffff;
    if((raw&0xffffff)!==local)fail();
    return id;
  }
  function winner(id,type) {
    const lookup=call('lookupEspmRecordById',id),record=lookup && lookup.record;
    if(!record || record.type!==type || mapped(lookup,record.id)!==id)fail();
    return lookup;
  }
  function resolveMerchant(reference,base) {
    try {
      const id=resolve(reference),baseId=resolve(base),placement=winner(id,'ACHR');
      const fields=placement.record.fields;
      if(!Array.isArray(fields))fail();
      const names=fields.filter(field=>field && field.type==='NAME');
      if(names.length!==1 || !(names[0].data instanceof Uint8Array) || names[0].data.byteLength!==4)fail();
      const data=names[0].data;
      const raw=Buffer.from(data.buffer,data.byteOffset,data.byteLength).readUInt32LE();
      if(mapped(placement,raw)!==baseId)fail();
      winner(baseId,'NPC_');
      return id;
    } catch(error) {fail();}
  }
  function validateInventory(snapshot) {
    try {if(call('validateInventoryTransaction',snapshot)!==true)fail();return true;}
    catch(error) {fail();}
  }
  return Object.freeze({resolveMerchant,validateInventory});
}
module.exports={createLedgerNativeValidators};
