'use strict';
// Build-time evidence for public delivery goods. Delivery never claims that
// the accepting character personally made or harvested the supplied items.
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const ranks=['novice','advanced','expert','master'];
const recipeFields=['owner','half','rank','out','makes','bench','inputItems','needs'];
function validateRankedQuests(doc,source) {
 const fail=()=>{throw Error('Ranked commission source evidence cannot be verified.');};
 doc=JSON.parse(JSON.stringify(doc));
 if(!doc||doc.version!==1||doc.active!==false||doc.complete!==false||!Array.isArray(doc.quests))fail();
 const ids=new Set(),objectives=new Set();
 for(const row of [...source.legacy,...doc.quests]) {
  if(!row||ids.has(row.id))fail();ids.add(row.id);
  if(row.kind==='commission') {
   const objective=row.goods.map(good=>good.item).sort().join('|');
   if(objectives.has(objective))fail();objectives.add(objective);
  }
 }
 return doc.quests.map(row=>{
  const tier=ranks.indexOf(row.tier),merchant=row.merchant;
  let gate;try{gate=source.gates.validate(row.gate);}catch(error){fail();}
  if(!/^q-[a-z0-9-]{1,46}$/.test(row.id)||typeof row.name!=='string'||!row.name.trim()||typeof row.text!=='string'||!row.text.trim()||
    row.kind!=='commission'||row.deliveryVersion!==2||tier<0||gate.open===true||gate.rank!==row.tier||
    row.cooldownHours!==[6,12,24,48][tier]||!same(row.reward,{source:'merchant-purse',pricing:'submitted-hold-price'})||
    !source.roster.some(candidate=>same(candidate,merchant))||!Array.isArray(row.goods)||row.goods.length<2||row.goods.length>5)fail();
  const table=source.roles.tables[merchant.role];let batches=0,masterBatches=0,highest=-1;
  const types={};
  for(const good of row.goods) {
   const record=source.roles.records[good.item];
   if(!record||record.flags&0x20||['ARMO','WEAP'].includes(record.type)&&record.flags&4||!table.buy.includes(good.item)||
     !Number.isSafeInteger(good.count)||good.count<1||good.count>100000||
     ['recipe','harvest','mining'].filter(key=>good[key]).length!==1)fail();
   types[good.item]=record.type;
   let rank;
   if(good.recipe) {
    const proof=good.recipe,actual=source.recipes[proof.reference];
    if(!actual||actual.fires!==true||actual.book==='cut'||actual.roll!==undefined||actual.race!==''||actual.inputsWithNoProducer!==0||actual.out!==good.item||
      !(source.roles.evidence[good.item]||[]).includes(actual.owner+':recipe:'+proof.reference+':out')||
      !same(proof,{reference:proof.reference,...Object.fromEntries(recipeFields.map(key=>[key,actual[key]]))})||
      !actual.inputItems.every(item=>item.suppliedBy&&ranks.indexOf(item.suppliedAt)>=0&&ranks.indexOf(item.suppliedAt)<=tier)||
      actual.owner!==merchant.role&&!(merchant.role==='Enchanter'&&
        (source.roles.evidence[good.item]||[]).includes('Enchanter:wardweaver:public-wearable')))fail();
    rank=ranks.indexOf(actual.rank);const quantity=Math.ceil(good.count/actual.makes);
    if(!Number.isSafeInteger(quantity)||quantity<1)fail();
    batches+=quantity;if(rank===3)masterBatches+=quantity;
   }else if(good.harvest) {
    const proof=good.harvest,actual=source.harvests[proof.reference];
    if(!actual||!same(proof,{reference:proof.reference,...actual})||actual.produce!==good.item||merchant.role!=='Alchemist')fail();
    rank=ranks.indexOf(actual.rank);
   }else {
    const proof=good.mining,actual=source.ores[proof.reference];
    if(!actual||!same(proof,{reference:proof.reference,...actual})||actual.ore!==good.item||
      merchant.role!=='Smith'||row.gate.classKey!=='miner')fail();
    rank=ranks.indexOf(actual.rank);
   }
   if(rank<0||rank>tier)fail();highest=Math.max(highest,rank);
  }
  if(Object.keys(types).length!==row.goods.length||highest<tier&&!(tier===3&&highest===2&&batches>=6)||
    tier===3&&highest===3&&masterBatches===1)fail();
  return {...row,itemTypes:types};
 });
}
module.exports={validateRankedQuests};
