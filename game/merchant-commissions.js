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
 'q-hjaalmarch-alchemist-cotton-dressings':'7dd3a8f94cecd900b4211180e69ed764bd684b32512d1d262ae97feb972b78a9'
});
function prepareCommissions(author,catalog,native) {
 if(!Array.isArray(author)||author.length!==Object.keys(publication).length)throw Error('Invalid published commission catalogue.');
 author=copy(author);catalog=copy(catalog);
 if(new Set(author.map(row=>row&&row.id)).size!==author.length||author.some(row=>{
   if(!row||publication[row.id]!==row.sourceHash)return true;
   const {sourceHash,itemType,...definition}=row;return hash(definition)!==sourceHash;
  }))
  throw Error('Published commission definitions must remain available.');
 const ids=new Set();
 return author.map(source=>{
  const row=copy(source),merchant=row.merchant,place=merchant&&catalog.byRef[merchant.reference];
  if(row.kind!=='commission'||row.tier!=='novice'||row.cooldownHours!==6||ids.has(row.id)||
    !place||place.role!==merchant.role||place.hold!==merchant.hold||place.bookHold!==merchant.bookHold||
    !Array.isArray(row.goods)||row.goods.length!==1||!row.reward||row.reward.source!=='merchant-purse'||
    row.reward.pricing!=='submitted-hold-price')throw Error('Commission source or appointed merchant cannot be verified.');
  ids.add(row.id);
  const good=row.goods[0];
  return {id:row.id,name:row.name,text:row.text,tier:row.tier,gate:row.gate,
   who:[row.gate.classKey||row.gate.profession,row.gate.half,row.gate.rank].filter(Boolean).join(', '),
   merchantId:native.resolveMerchant(merchant.reference,merchant.base),merchantRef:merchant.reference,
   role:merchant.role,hold:merchant.hold,bookHold:merchant.bookHold,
   itemId:native.resolveItem(good.item,row.itemType),itemDesc:good.item,count:good.count,sourceHash:row.sourceHash};
 });
}
function createCommissions(deps) {
 const rows=new Map(),now=deps.now||Date.now,purses=deps.purses,transfer=deps.transfer;
 for(const source of deps.rows||[]) {
  const row=copy(source);
  if(!/^q-[a-z0-9-]{1,46}$/.test(row.id)||rows.has(row.id)||!Number.isInteger(row.merchantId)||row.merchantId<=0||
    !Number.isInteger(row.itemId)||row.itemId<=0||row.itemId===15||!Number.isSafeInteger(row.count)||row.count<1||row.count>100000||
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
 function quoted(row) {
  const catalog=deps.prices.catalog(row.bookHold)||[],matches=[];
  for(const item of catalog) {
   const resolved=deps.resolve(item.name);
   if(resolved&&!resolved.error&&resolved.baseId===row.itemId) {
    const price=deps.prices.quote(row.bookHold,item.name);
    if(price&&Number.isSafeInteger(price.buy)&&price.buy>=0&&price.buy<=2147483647&&
      Number.isSafeInteger(price.buy*row.count)&&price.buy*row.count<=2147483647)
     matches.push({unit:price.buy,name:resolved.name||item.name});
   }
  }
  // Ambiguous names or two aliases are never a guess at an accepted promise.
  return matches.length===1?matches[0]:null;
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
   const original=held||pending,quote=original?{unit:original.unit,name:original.item.name}:quoted(row);
   const gate=original?true:eligible(actor,row),waiting=!!state.pending;
   const cooldown=last&&at-last<STATE.WAIT;
   const enough=!!original&&INVENTORY.inventory(transfer.inventory(actor)).entries.filter(item=>item.baseId===row.itemId)
     .reduce((sum,item)=>sum+item.count,0)>=original.count;
   const open=!!original,openLimit=STATE.openCount(namespace(),human)>=3;
   const activeCool=Object.keys(jobs.cool).filter(key=>at-jobs.cool[key]<STATE.WAIT).length;
   const room=jobs.serial<Number.MAX_SAFE_INTEGER&&Object.keys(jobs.held).length<STATE.MAX_HELD&&
     Object.keys(jobs.held).length+activeCool<STATE.MAX_COOL;
   const funds=quote&&STATE.spendable(state)>=quote.unit*row.count;
   const ready=deps.settlement.available()&&deps.settlement.canInventoryMutation(actor);
   const reason=waiting?'This trader is finishing a saved transfer.':!ready?'Trading is waiting for a saved inventory.':
     !gate?'You do not meet this work\'s requirements.':cooldown?'This work is still resting.':!quote?'No submitted buy price is available for this work.':
     !open&&openLimit?'You already hold three commissions.':!open&&!room?'This trader cannot accept more work yet.':
     !open&&!funds?'The trader cannot reserve this payment.':'';
   result.push({id:row.id,name:row.tier[0].toUpperCase()+row.tier.slice(1)+': '+row.name,kind:'commission',
    who:row.who,check:row.text+' '+reason,locations:row.hold+'; return to this '+row.role+'.',exactMerchant:true,
    state:open?'open':cooldown?'cooldown':!gate?'locked':reason?'unavailable':'available',
    hours:6,count:row.count,item:quote?quote.name:row.itemName||'the requested goods',gold:quote?quote.unit*row.count:null,
    quotedUnit:quote?quote.unit:null,token:original?original.token:null,waiting:waiting,
    waitMinutes:cooldown?Math.ceil((STATE.WAIT-at+last)/60000):0,
    canTake:!open&&!reason,canReturn:open&&!waiting&&ready&&enough,canAbandon:open&&!waiting&&ready});
  }
  return result;
 }
 function act(actor,merchant,verb,id,argument,guards) {
  const row=rows.get(id),ctx=context(actor,merchant,row);
  if(!ctx||!guards||typeof guards.current!=='function'||typeof guards.alive!=='function')return {ok:false,why:'session'};
  const {state,human,key,jobs}=ctx;
  if(state.pending||!deps.settlement.available()||!deps.settlement.canInventoryMutation(actor))return {ok:false,why:'waiting'};
  if(typeof argument!=='string'||!/^@(0|[1-9][0-9]*)$/.test(argument))return {ok:false,why:'session'};
  const number=Number(argument.slice(1));if(!Number.isSafeInteger(number))return {ok:false,why:'session'};
  function current(fresh,quote) {
   if(!guards.current()||STATE.owner(transfer.identity(actor))!==STATE.owner(human))return false;
   if(fresh) {
    const again=quoted(row);
    if(!again||again.unit!==quote.unit||again.name!==quote.name||!eligible(actor,row))return false;
   }
   const count=STATE.openCount(namespace(),human);
   return (!fresh||count<3)&&guards.current()&&guards.alive();
  }
  if(verb==='take') {
   if(!eligible(actor,row))return {ok:false,why:'eligibility'};
   const quote=quoted(row);if(!quote||quote.unit!==number)return {ok:false,why:'price'};
   if(STATE.openCount(namespace(),human)>=3)return {ok:false,why:'open-limit'};
   const terms={hash:row.sourceHash,item:{baseId:row.itemId,name:quote.name},count:row.count,unit:quote.unit},at=now();
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
  if(held.hash!==row.sourceHash||held.item.baseId!==row.itemId||held.count!==row.count)return {ok:false,why:'recovery'};
  const completed=STATE.finish(jobs,human,id,number,now());if(!completed.ok)return completed;
  const expected=INVENTORY.inventory(transfer.inventory(actor));
  let outgoing;try{outgoing=INVENTORY.takeEntries(expected,held.item.baseId,held.count);}catch(error){return {ok:false,why:'short'};}
  const stock=deps.addStock(copy(state.stock),outgoing.entries,held.item.name);
  const next={purse:state.purse-held.gold,stock,supply:copy(state.supply||{}),commissions:completed.next};
  const moved=deps.settlement.begin({merchantId:merchant,humanId:actor,profileId:human.profileId,kind:'commission',
   previous:state,next,expected,debit:outgoing.inventory,credit:held.gold?[{baseId:15,count:held.gold}]:[],caller:()=>current(false)});
  return {ok:!!moved.done,why:moved.done?'':'waiting'};
 }
 return {has:id=>rows.has(id),view,act};
}
module.exports={createCommissions,prepareCommissions,publication};
