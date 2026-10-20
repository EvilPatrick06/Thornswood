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
 'q-whiterun-enchanter-commission-rack':'531aabc2aaf3355f9867da014fb417e68b0a6171df577e82d7b39b61c5713787',
 'q-whiterun-smith-steel-blade-set':'b40b831c7c694b54bc1ae5d771e78136855044c542e78c02b492d0232970a43c',
 'q-whiterun-smith-glass-defence':'014841f818c26e6d1cf81ce9343f7554256fe0f12fd649d27d0a21a3e8ff91d3',
 'q-whiterun-woodworker-first-water-kit':'853bb28de7faec0ea0bdf90055369f01567e22b984055c9c835994db1c38ed06',
 'q-whiterun-woodworker-orcish-bow-kit':'7bdfd4fe29bd068d09aca13dddb8622317c7dda4d7410a07876a0bce1799d72c',
 'q-whiterun-woodworker-briquette-tools':'40fc07a8bd93a29fdaabc2cbbeb9fc97ac872cf2cafdbd8dfbe61341575c3507',
 'q-whiterun-tailor-hunt-feast-ribbons':'ebc1fece8c87c358e29c25945d428355036fd4bfe89d2c220c4f630d78b9ad89',
 'q-whiterun-tailor-white-fur-trimmings':'c914eff5b96246ef00a834b319b63d4289ba6f8c925c85220d732a0ca083f4f4',
 'q-whiterun-enchanter-glass-blade-supplies':'9b7585d22ff171b69fdd036ac4a72b191f34797d92350b77dde6c766d24eab37',
 'q-whiterun-cook-field-meal-parcel':'2ea942805da47f530b5bacfac762e1d6fa70c4c2f8d04603e0d06b266c977d79',
 'q-whiterun-cook-tomato-bread-order':'cc4f4f0682b62ef1b3029f500cf17baa8aa0fe689e93bbeaaf7e58260adcff63',
 'q-whiterun-cook-apple-dessert-order':'8abf81285bad8141f47e8908b28158537dd2856e240ba88317a541ede5411ddf',
 'q-whiterun-alchemist-lavender-cotton':'67ab5bbdfc39ab76203ab4b745ee9273277966436811ea357144d99efa1107ae',
 'q-whiterun-alchemist-fungal-collection':'5cb145a895c223d243bdb074f7ff5bd9f5704b75567358fbfab6b87105d87286',
 'q-solitude-smith-novice-parcel':'df7211e51512ad2baaa9b5ac808534cbb2dee4665a81d44fd152ef57a4128efb',
 'q-solitude-smith-advanced-parcel':'a1822b9c559eaf81c5b344087327bc324763cc4a0d7892086822c7962bb7ef09',
 'q-solitude-smith-expert-parcel':'c83f6c333a4a6dab26d77b3060a501ea3410e374148fe6cfe9f82e4ebe7de1d5',
 'q-solitude-smith-master-parcel':'145ec5099550e94b549a8467002eda9be6a95f0013a9c098e15a755f1059b52f',
 'q-solitude-woodworker-novice-parcel':'eff78b719516104c504065fd236abc5b5cf6a0b55aa7dd6d3d73e62acd6c0618',
 'q-solitude-woodworker-advanced-parcel':'5c670ce213b54dda267885e71d68fa98c1e4ff3a26cecef57da5a6bb0e451483',
 'q-solitude-woodworker-expert-parcel':'83b5039ab24f758b03542d82e36e998b802bdb098b788985ba860d84a5714efc',
 'q-solitude-woodworker-master-parcel':'8adf898f6904b8c48693a6f36d3e8979735774b25aa9f23f95756af1722d5af0',
 'q-solitude-tailor-novice-parcel':'46b2bf83e16e8d6d299de0cfdcdcdb5f6ff8f4a3eee8c4165ba868f0671991a6',
 'q-solitude-tailor-advanced-parcel':'038aee1d0874634bcb1f5410763aa71259d615d33fdd4fcac6889d2dfc2e376b',
 'q-solitude-tailor-expert-parcel':'601b656ab3906df24a575a3b11ba3e4c8dfb09fe735b3e75ae8074948989b2f9',
 'q-solitude-tailor-master-parcel':'a6874618ac393fcd1a3de174792564c72f47c6476e56b9a8b2eb5b0c14f05e27',
 'q-solitude-enchanter-novice-parcel':'b85aa9d71e3ba84bc5b330d03f072ba776dc684433d5c9eb6028619d3bcfedc1',
 'q-solitude-enchanter-advanced-parcel':'62e017232f60eaa1d8700b6a252fdd8666a6107484468230df7fd5d48936edec',
 'q-solitude-enchanter-expert-parcel':'c1c516c4149e23ad465a01b897204fcf6891ff936d37a0c531df677bc368db93',
 'q-solitude-enchanter-master-parcel':'4236b0aca6430b17ade65b1f5b179af42239b4bff0479ebd00d9e18271f2f3a4',
 'q-solitude-cook-advanced-parcel':'1772d5bb9a497f7a3b4f4e62f17685cabb682b6145148686eee210e43a7e85b9',
 'q-solitude-cook-expert-parcel':'ae91b7abf34c51b21fca3089f4e7cde187cb9b4d410e28a99d6d6df36024c347',
 'q-solitude-cook-master-parcel':'ff3025444aa93d780a488a686069767b5498561284d7c0629779648c335e7ad0',
 'q-solitude-alchemist-novice-parcel':'5265cf07dd4493c7f21fadedbd79350e672da0ff1adf0aa24edc1c351b8edb84',
 'q-solitude-alchemist-advanced-parcel':'d20cdc3ff2441af5c52ca3fe7851a990f0345775198676024aed996090455cb5',
 'q-solitude-alchemist-expert-parcel':'82035e27fa5993ef137a44bf22a566121e67593bbfc9ceb6e944707ae7a719fb',
 'q-solitude-alchemist-master-parcel':'d02aaac889785a16a365c3eca50b9e955bd94a9e5721451471ac8c70227d88fd',
 'q-riften-smith-novice-parcel':'147aaf8482e18415ffc9f5bbace4bae68cbde751325b5b04f230c30e68ac24d4',
 'q-riften-smith-advanced-parcel':'f9e445a8711b9825fd5117b8f74299d58daa5b3f66eeb190a96e51bb2b892a8c',
 'q-riften-smith-expert-parcel':'956c8368cb647136fed47901da4fed2c6286b4821463eeea7060e162b6beb9d1',
 'q-riften-smith-master-parcel':'e3bb684140354c61c7fc6c98dae1afa6a83fce572a9d3eea424b128940241fae',
 'q-riften-woodworker-advanced-parcel':'76b9aee0436ca6224778be010a1b7f2678550bbfdf7211c0be646c20c7098b71',
 'q-riften-woodworker-expert-parcel':'9c9f0785246cbeb2375a4b4b13ed8be5e35db225c7a8c744d90ea8cc904e3ae2',
 'q-riften-woodworker-master-parcel':'bb78ef69e73338888a8b5a28d1275a2d97b94af1172a2c823c92d39a89bf8342',
 'q-riften-tailor-novice-parcel':'f688f2a5c8441d986603744c398a860b7525f5d6404183e6dea517504dc6013c',
 'q-riften-tailor-expert-parcel':'385d0c7577db65393ab4e08e94429e338ba8e34499fc60d715eaa92751ccf6e4',
 'q-riften-tailor-master-parcel':'cbe99b87e92481de6f5ebcf35f8f842dae8711f919c3397f1c7fc201f41505d7',
 'q-riften-enchanter-novice-parcel':'2e3386850953c862108bf1f33b5d45cb5a5ca39d0579a379520d7867a166fe6d',
 'q-riften-enchanter-advanced-parcel':'5170503cc1f9a7ad816967c3409aece3c4101c37f7a7dffb705e8fe54544ae92',
 'q-riften-enchanter-expert-parcel':'9638f8521d601c8bb16ddde88ce0b82e5f5c187b8d246c59c1aaa51e41c1bae3',
 'q-riften-enchanter-master-parcel':'908deb3f07b96655711c7a4a2bb61988cedaec07fc1c17f8ad968786a0fc0fca',
 'q-riften-cook-novice-parcel':'60489099acb4ad46a6c24ba853b3e587bb62e032958999dc838d5a3dccff84e9',
 'q-riften-cook-advanced-parcel':'e7ca3fe3b22483768aa7a965db571d4af1f2b693aee1e96dc9e0ef6eafac6273',
 'q-riften-cook-expert-parcel':'175b846701a3bc02080ba416438060d794a838ed6839e7d4221d1b32ad15014a',
 'q-riften-cook-master-parcel':'79a05e34b25a2cbf20ca03d6e5227d746a031aafbfed701c46012cce6ce6cf8c',
 'q-riften-alchemist-novice-parcel':'babcd40296416c5a92a0887b832b5c2d5e4572ba790bb76134eb4efcd3337134',
 'q-riften-alchemist-advanced-parcel':'3e8cea381c48b8ceab960e61e9c10e26b5b13a4f558a5d0fb9b22c8d65e66100',
 'q-riften-alchemist-expert-parcel':'890f7cfc2c431c5cfbefc78c7bdef92dc41d0bacbe3ef675f7d4017359433755',
 'q-riften-alchemist-master-parcel':'78a27b84dc9d0aaaa649264dd908a952b0212b2029aa49bd9ffcfb8d0de802b0',
 'q-markarth-smith-novice-parcel':'fc2122cf0cf6c6e988886fb8a4011aa2d286eeff2a9db9ecd12ea35d67113259',
 'q-markarth-smith-advanced-parcel':'7cd6771000f07fd8fab7060d145c07f784d278d0d8935027c73bff65d45a7449',
 'q-markarth-smith-expert-parcel':'9f8a055c39abe1c6da78e026d06439129cb9209423504f58d10aab4011fd5a2d',
 'q-markarth-smith-master-parcel':'f9b1854ae2954c03148c0953b29b7f03077aee9842b9a0405a4340d8ff388bec',
 'q-markarth-woodworker-novice-parcel':'8a14d28f769296a7779f86bfe78517a8388e58d86feded698a791cbcefe9538e',
 'q-markarth-woodworker-advanced-parcel':'83dc5ab0d102b917460dc3ad68b39b8ea25dffaf511f6f0b520356b6b3dd931b',
 'q-markarth-woodworker-expert-parcel':'2bdfa338694777b2af3bf7dad169013e990a12f7b92c1c3bc3fb417b0eff8c69',
 'q-markarth-woodworker-master-parcel':'8378ba65a73153a84b4a6dbde433ed97caf1cbd4d3e4167ce52bc5fe8da8c538',
 'q-markarth-tailor-novice-parcel':'41d6dcf835ba00f47aad39321873750c027453c2f72770f22ac49665b6d7c42b',
 'q-markarth-tailor-advanced-parcel':'3575fb5956c6bfca509b104b5ea5c869b396deea02183b6993e379251fb5b463',
 'q-markarth-tailor-expert-parcel':'a82db75d4c592db004bcdc23e84c5df26ebe1d11ae86d6e84c87b43925760e23',
 'q-markarth-tailor-master-parcel':'d1c3e3fc5101c91621156be66ebb239bc6b230a35308110dcf589c3fdfec86f7',
 'q-markarth-enchanter-novice-parcel':'f4e8deb7f06db5fcbb86b7bea4ce92e6653822e8db470658fd7bd7fb5e7ac78a',
 'q-markarth-enchanter-advanced-parcel':'d512ed14fd1ff31a91572773f99f72de06a4ff8a403c6fbfd881df6e3921ca27',
 'q-markarth-enchanter-expert-parcel':'ae00a0f4ac01f6369331c039a5ff2613a260a67a08e368265f368bbd6dcb9084',
 'q-markarth-enchanter-master-parcel':'ab4c44e94cfb2fb9282dbceda00ceed78b916eb835cc9b13db53c48bc6becc4a',
 'q-markarth-cook-novice-parcel':'5fd53334c226ce6704106b241bc57cdee0d55ed51fc8183aff35703ac0631b10',
 'q-markarth-cook-advanced-parcel':'d1ffb9be87476f061d36e9014350dc72dacb9eee866b4a2e483f9e68dea3732e',
 'q-markarth-cook-expert-parcel':'afdedf75a9443c1a240eeda12e43c19e1a97ee2ccceb99f2036dd9041020b751',
 'q-markarth-cook-master-parcel':'1d9726f66c9475f243dd98c2ad8b5413531d9872e8a2c0f3d236b05e30889f24',
 'q-markarth-alchemist-novice-parcel':'d9f9e50d28fba45eaa5d3f7ffff68474e92931bbbbbdf5ea764ed75fee3e3744',
 'q-markarth-alchemist-advanced-parcel':'d3f55b2c5c9c66b6155d646e31cd8284c847945823f3a6b31253299c2e936b6a',
 'q-markarth-alchemist-expert-parcel':'a12e438d237306c6281f5e532e80c4bf3aebf604ae1cd50f3792fe3588a5b100',
 'q-markarth-alchemist-master-parcel':'f46347e9e2a02ba39a843d35a3bd8bcda9a063d0f98cd85830c439486c2cf419'
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
