'use strict';
const STATE=typeof MERCHANT_COMMISSION_STATE!=='undefined'?MERCHANT_COMMISSION_STATE:require('./merchant-commission-state');
const INVENTORY=typeof MERCHANT_SETTLEMENT!=='undefined'?MERCHANT_SETTLEMENT:require('./merchant-settlement');
const copy=value=>JSON.parse(JSON.stringify(value));
const hash=value=>require('node:crypto').createHash('sha256').update(JSON.stringify(value)).digest('hex');
// Published jobs remain routable while their accepted promises exist.
const publication=Object.freeze({
 'q-whiterun-smith-straps':'8f03bdc903aaf1e37727f54a3e49bfdea5a2b817bc7534ba0111c88d25502734',
 'q-rift-woodworker-hunt-arrows':'84b31663cd265c9b26068ff7343622f04b332ddce394e58b52a55b0b6cbb3a89',
 'q-falkreath-tailor-mourning-thread':'8dded80c9b0e56c8a18158136ca200481a444582a41cc98000fe8ad612ec0aef',
 'q-haafingar-cook-dock-supper':'cfd57250d82ce20c23fa8db5c802509e103d6dd8c0e0a55654b1ed4da12c8a11',
 'q-hjaalmarch-alchemist-marsh-poultices':'5b8b08e462680c7249f9359498a84f1e1ccbc7ff30020ed1d15fbdd204703652',
 'q-whiterun-smith-spare-pick':'df7c54b9f75be97be6c525080c59640af7448efa017dc9d3ed0c7d5c649f00b0',
 'q-rift-woodworker-spare-pole':'5c443c243872afe4c5068bc66345def10fc3efdb3c4bb8291a4bc2222c1f2e74',
 'q-falkreath-tailor-trail-boots':'c80cf0cfa03d0d7bbd02dac97a3ba10a92d6b112c6f18a21df6c77404e22acb1',
 'q-haafingar-cook-field-soup':'7f3e208a1bf02b1e44e007a77e18baa712e74a70c12c06efeea716f6af0210ac',
 'q-hjaalmarch-alchemist-cotton-dressings':'7dd3a8f94cecd900b4211180e69ed764bd684b32512d1d262ae97feb972b78a9',
 'q-whiterun-smith-ebony-seam-account':'d09451fa3306f0743d0e68bd78ae43bde11dcd0fdc2761abe37c350d37a70faa',
 'q-whiterun-woodworker-outfitter-reserve':'a94934368484eaf0bcfa65564909260c8b1da3e198a11495b31a8d1c070836e0',
 'q-whiterun-tailor-winter-vestments':'68f0406f1fe3db80d3b820d13413c0419a960da038eef3a54ac103091d9af2e0',
 'q-whiterun-enchanter-ward-demonstration':'8f19b0da990fc2102dd312016717dc92a48f23d6bcfdec622aaf3adc621d169e',
 'q-whiterun-cook-mammoth-supper':'d8731860a77c3864c7b01ab6fa45c5311e0dfc1b68e8fbfec91e7b2b34fab5d4',
 'q-whiterun-alchemist-ash-expedition':'75d2ee9fbfc5902fe6b9d200feeb7ede1b0773d57c1dbad4e6b14db5b11479df',
 'q-whiterun-alchemist-travelling-case':'7131990508cefa6f7c7601227b888ed4f4c70c28990dda2a863b37436760a9da',
 'q-whiterun-enchanter-commission-rack':'531aabc2aaf3355f9867da014fb417e68b0a6171df577e82d7b39b61c5713787'
});
function prepareCommissions(author,catalog,native) {
 if(!Array.isArray(author)||author.length!==Object.keys(publication).length)throw Error('Invalid published commission catalogue.');
 author=copy(author);catalog=copy(catalog);
 if(new Set(author.map(row=>row&&row.id)).size!==author.length||author.some(row=>{
   if(!row||publication[row.id]!==row.sourceHash)return true;
   const {sourceHash,itemType,itemTypes,...definition}=row;return hash(definition)!==sourceHash;
  }))
  throw Error('Published commission definitions must remain available.');
 const ids=new Set();
 return author.map(source=>{
  const row=copy(source),merchant=row.merchant,place=merchant&&catalog.byRef[merchant.reference];
  const bundle=row.deliveryVersion===2;
  if(row.kind!=='commission'||!['novice','advanced','expert','master'].includes(row.tier)||
    row.cooldownHours!==[6,12,24,48][['novice','advanced','expert','master'].indexOf(row.tier)]||ids.has(row.id)||
    !place||place.role!==merchant.role||place.hold!==merchant.hold||place.bookHold!==merchant.bookHold||
    !Array.isArray(row.goods)||row.goods.length<(bundle?2:1)||row.goods.length>(bundle?5:1)||!row.reward||row.reward.source!=='merchant-purse'||
    row.reward.pricing!=='submitted-hold-price')throw Error('Commission source or appointed merchant cannot be verified.');
  ids.add(row.id);
  const good=row.goods[0];
  return {id:row.id,name:row.name,text:row.text,tier:row.tier,gate:row.gate,
   who:[row.gate.classKey||row.gate.profession,row.gate.half||row.gate.school,row.gate.rank].filter(Boolean).join(', '),
   merchantId:native.resolveMerchant(merchant.reference,merchant.base),merchantRef:merchant.reference,
   role:merchant.role,hold:merchant.hold,bookHold:merchant.bookHold,
   ...(bundle?{deliveryVersion:2,hours:row.cooldownHours,goods:row.goods.map(part=>({
     itemId:native.resolveItem(part.item,row.itemTypes[part.item]),itemDesc:part.item,count:part.count}))}:
     {itemId:native.resolveItem(good.item,row.itemType),itemDesc:good.item,count:good.count}),sourceHash:row.sourceHash};
 });
}
function createCommissions(deps) {
 const rows=new Map(),now=deps.now||Date.now,purses=deps.purses,transfer=deps.transfer;
 for(const source of deps.rows||[]) {
  const row=copy(source);
  const goods=row.deliveryVersion===2?row.goods:[row];
  if(!/^q-[a-z0-9-]{1,46}$/.test(row.id)||rows.has(row.id)||!Number.isInteger(row.merchantId)||row.merchantId<=0||
    !Array.isArray(goods)||goods.length<1||goods.length>5||new Set(goods.map(good=>good.itemId)).size!==goods.length||
    goods.some(good=>!Number.isInteger(good.itemId)||good.itemId<=0||good.itemId===15||
      !Number.isSafeInteger(good.count)||good.count<1||good.count>100000)||
    row.deliveryVersion===2&&![6,12,24,48].includes(row.hours)||
    typeof row.sourceHash!=='string'||!/^[0-9a-f]{64}$/.test(row.sourceHash)||typeof row.role!=='string'||!row.role)
   throw Error('Published commission authority cannot be verified.');
  rows.set(row.id,row);
 }
 function namespace() {
  if(purses.callerGuard!==true||typeof purses.ledgerStates!=='function'||typeof purses.stats!=='function')
   throw Error('Commission ledger admission is unavailable.');
  const stats=purses.stats(),all=purses.ledgerStates(),size=stats.catalogue+(stats.retired||0);
  if(!Array.isArray(all)||!Number.isInteger(size)||size<1||size>249||all.length!==size||
    new Set(all.map(row=>row.reference)).size!==size)throw Error('The complete commission ledger cannot be verified.');
  return all.filter(row=>row.state!==null).map(row=>{STATE.spendable(row.state);return row.state;});
 }
 function quoteGood(row,good) {
  const catalog=deps.prices.catalog(row.bookHold)||[],matches=[];
  for(const item of catalog) {
   const resolved=deps.resolve(item.name);
   if(resolved&&!resolved.error&&resolved.baseId===good.itemId) {
    const price=deps.prices.quote(row.bookHold,item.name);
    if(price&&Number.isSafeInteger(price.buy)&&price.buy>=0&&price.buy<=2147483647&&
      Number.isSafeInteger(price.buy*good.count)&&price.buy*good.count<=2147483647)
     matches.push({unit:price.buy,name:resolved.name||item.name});
   }
  }
  // Ambiguous names or two aliases are never a guess at an accepted promise.
  return matches.length===1?matches[0]:null;
 }
 function quoted(row) {
  const parts=row.deliveryVersion===2?row.goods:[row],goods=[];
  for(const part of parts) {
   const quote=quoteGood(row,part);if(!quote)return null;
   goods.push({item:{baseId:part.itemId,name:quote.name},count:part.count,unit:quote.unit});
  }
  const gold=goods.reduce((sum,good)=>sum+good.count*good.unit,0);
  if(!Number.isSafeInteger(gold)||gold>2147483647)return null;
  return {goods,gold,argument:row.deliveryVersion===2?hash([row.sourceHash,goods]):String(goods[0].unit)};
 }
 function promised(row,held) {
  const goods=held.goods||[{item:held.item,count:held.count,unit:held.unit}];
  const parts=row.deliveryVersion===2?row.goods:[row];
  return held.hash===row.sourceHash&&goods.length===parts.length&&goods.every((part,i)=>
   part.item.baseId===parts[i].itemId&&part.count===parts[i].count)&&
   (row.deliveryVersion===2?held.hours===row.hours:held.goods===undefined);
 }
 function eligible(actor,row) {return typeof deps.eligible==='function'&&deps.eligible(actor,row.gate)===true;}
 function context(actor,merchant,row) {
  if(!row||row.merchantId!==merchant)return null;
  const state=purses.read(merchant),human=transfer.identity(actor);
  if(!state||state.reference!==row.merchantRef||!STATE.owner(human))return null;
  STATE.spendable(state);
  return {state,human,key:STATE.key(human,row.id),jobs:STATE.read(state.commissions)};
 }
 function view(actor,merchant) {
  const result=[];
  for(const row of rows.values()) {
   const ctx=context(actor,merchant,row);if(!ctx)continue;
   const {state,human,key,jobs}=ctx,held=jobs.held[key],last=jobs.cool[key],at=now();
   const pending=state.pending&&state.pending.kind==='commission'&&state.pending.human&&
     STATE.owner(state.pending.human)===STATE.owner(human)&&state.pending.previous.commissions&&
     state.pending.previous.commissions.held[key];
   const original=held||pending,quote=original?{goods:original.goods||[{item:original.item,count:original.count,unit:original.unit}],gold:original.gold}:quoted(row);
   const gate=original?true:eligible(actor,row),waiting=!!state.pending;
   const cooldown=last&&at-STATE.cooldownAt(last)<STATE.cooldownWait(last);
   const inventory=original?INVENTORY.inventory(transfer.inventory(actor)):null;
   const enough=!!original&&quote.goods.every(good=>inventory.entries.filter(item=>item.baseId===good.item.baseId)
     .reduce((sum,item)=>sum+item.count,0)>=good.count);
   const open=!!original,openLimit=STATE.openCount(namespace(),human)>=3;
   const activeCool=Object.keys(jobs.cool).filter(key=>at-STATE.cooldownAt(jobs.cool[key])<STATE.cooldownWait(jobs.cool[key])).length;
   const room=jobs.serial<Number.MAX_SAFE_INTEGER&&Object.keys(jobs.held).length<STATE.MAX_HELD&&
     Object.keys(jobs.held).length+activeCool<STATE.MAX_COOL;
   const funds=quote&&STATE.spendable(state)>=quote.gold;
   const ready=deps.settlement.available()&&deps.settlement.canInventoryMutation(actor);
   const reason=waiting?'This trader is finishing a saved transfer.':!ready?'Trading is waiting for a saved inventory.':
     !gate?'You do not meet this work\'s requirements.':cooldown?'This work is still resting.':!quote?'No submitted buy price is available for this work.':
     !open&&openLimit?'You already hold three commissions.':!open&&!room?'This trader cannot accept more work yet.':
     !open&&!funds?'The trader cannot reserve this payment.':'';
   result.push({id:row.id,name:row.tier[0].toUpperCase()+row.tier.slice(1)+': '+row.name,kind:'commission',
    who:row.who,check:row.text+' '+reason,locations:row.hold+'; return to this '+row.role+'.',exactMerchant:true,
    state:open?'open':cooldown?'cooldown':!gate?'locked':reason?'unavailable':'available',
    hours:original&&original.hours||row.hours||6,count:row.count,item:quote?quote.goods[0].item.name:row.itemName||'the requested goods',gold:quote?quote.gold:null,
    goods:row.deliveryVersion===2?(row.goods.map((part,i)=>({count:part.count,name:quote?quote.goods[i].item.name:part.itemDesc}))):undefined,
    quoteToken:row.deliveryVersion===2&&quote&&!original?quote.argument:null,
    quotedUnit:row.deliveryVersion!==2&&quote?quote.goods[0].unit:null,token:original?original.token:null,waiting:waiting,
    waitMinutes:cooldown?Math.ceil((STATE.cooldownWait(last)-at+STATE.cooldownAt(last))/60000):0,
    canTake:!open&&!reason,canReturn:open&&!waiting&&ready&&enough,canAbandon:open&&!waiting&&ready});
  }
  return result;
 }
 function act(actor,merchant,verb,id,argument,guards) {
  const row=rows.get(id),ctx=context(actor,merchant,row);
  if(!ctx||!guards||typeof guards.current!=='function'||typeof guards.alive!=='function')return {ok:false,why:'session'};
  const {state,human,key,jobs}=ctx;
  if(state.pending||!deps.settlement.available()||!deps.settlement.canInventoryMutation(actor))return {ok:false,why:'waiting'};
  if(typeof argument!=='string')return {ok:false,why:'session'};
  const number=/^@(0|[1-9][0-9]*)$/.test(argument)?Number(argument.slice(1)):NaN;
  if(!(verb==='take'&&row.deliveryVersion===2? /^@[0-9a-f]{64}$/.test(argument):Number.isSafeInteger(number)))return {ok:false,why:'session'};
  function current(fresh,quote) {
   if(!guards.current()||STATE.owner(transfer.identity(actor))!==STATE.owner(human))return false;
   if(fresh) {
    const again=quoted(row);
    if(!again||again.argument!==quote.argument||!eligible(actor,row))return false;
   }
   const count=STATE.openCount(namespace(),human);
   return (!fresh||count<3)&&guards.current()&&guards.alive();
  }
  if(verb==='take') {
   if(!eligible(actor,row))return {ok:false,why:'eligibility'};
   const quote=quoted(row);if(!quote||'@'+quote.argument!==argument)return {ok:false,why:'price'};
   if(STATE.openCount(namespace(),human)>=3)return {ok:false,why:'open-limit'};
   const terms=row.deliveryVersion===2?{hash:row.sourceHash,goods:quote.goods,hours:row.hours}:
     {hash:row.sourceHash,...quote.goods[0]},at=now();
   const accepted=STATE.reserve(jobs,human,id,terms,at,state.purse);
   if(!accepted.ok)return accepted;
   const next=Object.assign({},state,{commissions:accepted.next});
   const saved=deps.settlement.changeCommissions(merchant,state,next,human,()=>current(true,quote),{kind:'reserve',job:id,terms,at});
   return {ok:!!saved,why:saved?'':'session'};
  }
  const held=jobs.held[key];
  if(!held||held.token!==number)return {ok:false,why:'session'};
  if(verb==='abandon') {
   const at=now(),released=STATE.cancel(jobs,human,id,number,at);if(!released.ok)return released;
   const saved=deps.settlement.changeCommissions(merchant,state,Object.assign({},state,{commissions:released.next}),human,()=>current(false),
     {kind:'cancel',job:id,token:number,at});
   return {ok:!!saved,why:saved?'':'session'};
  }
  if(verb!=='return')return {ok:false,why:'request'};
  if(!promised(row,held))return {ok:false,why:'recovery'};
  const completed=STATE.finish(jobs,human,id,number,now());if(!completed.ok)return completed;
  const expected=INVENTORY.inventory(transfer.inventory(actor));
  let debit=expected,stock=copy(state.stock);
  try {
   for(const good of held.goods||[{item:held.item,count:held.count,unit:held.unit}]) {
    const outgoing=INVENTORY.takeEntries(debit,good.item.baseId,good.count);
    debit=outgoing.inventory;stock=deps.addStock(stock,outgoing.entries,good.item.name);
   }
  }catch(error){return {ok:false,why:'short'};}
  const next={purse:state.purse-held.gold,stock,supply:copy(state.supply||{}),commissions:completed.next};
  const moved=deps.settlement.begin({merchantId:merchant,humanId:actor,profileId:human.profileId,kind:'commission',
   previous:state,next,expected,debit,credit:held.gold?[{baseId:15,count:held.gold}]:[],caller:()=>current(false)});
  return {ok:!!moved.done,why:moved.done?'':'waiting'};
 }
 return {has:id=>rows.has(id),view,act};
}
module.exports={createCommissions,prepareCommissions,publication};
