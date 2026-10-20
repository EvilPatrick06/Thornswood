'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const gm=fs.readFileSync(path.join(__dirname,'../game/gamemode.js'),'utf8'),progression={};
vm.runInNewContext(gm.slice(gm.indexOf('// ==== thornswood progression ===='),gm.indexOf('// ==== end thornswood progression ====')),progression);
const gates=require('../game/quest-eligibility').createQuestEligibility({table:progression.__thornswoodProgression.TABLE,
 spellIds:progression.__thornswoodProgression.SPELL_IDS});
const {validateRankedQuests}=require('../scripts/dev/MerchantQuestSources');
const load=name=>require('../game/data/'+name+'.json'),copy=value=>JSON.parse(JSON.stringify(value));
const doc=load('merchant-ranked-quests'),source={legacy:load('merchant-quests').quests,roster:load('merchant-roster').merchants,
 roles:load('merchant-role-tables'),gates,recipes:load('recipes').recipes,harvests:load('harvests').harvests,ores:load('ores').ores};
assert.equal(validateRankedQuests(doc,source).length,90);
for(const defect of ['source','quantity','price','merchant','tier','duplicate','half-source','missing-part','difficulty','held','gate','school','class-half','public-proof','other-logistics','lower-producer','lower-recipe','copied-logistics']) {
 const broken=copy(doc),sources={...copy(source),gates};
 if(defect==='source')broken.quests[0].goods[0].mining.rank='novice';
 if(defect==='quantity')broken.quests[0].goods[0].count=0;
 if(defect==='price')broken.quests[0].reward.pricing='invented-price';
 if(defect==='merchant')broken.quests[0].merchant.base='10:Skyrim.esm';
 if(defect==='tier')broken.quests[0].tier='novice';
 if(defect==='duplicate')broken.quests.push(copy(broken.quests[0]));
 if(defect==='half-source')broken.quests[1].goods[0].recipe.half='Charburner';
 if(defect==='missing-part')broken.quests[0].goods.length=1;
 if(defect==='difficulty')broken.quests[2].goods.forEach(g=>g.count=1);
 if(defect==='held')sources.roles.records[broken.quests[0].goods[0].item].flags|=0x20;
 if(defect==='gate')delete broken.quests[1].gate.half;
 if(defect==='school')broken.quests[3].gate.school='invented';
 if(defect==='class-half')broken.quests[0].gate.half='edgewright';
 if(defect==='public-proof') {
  const good=broken.quests[1].goods[0];sources.roles.evidence[good.item]=sources.roles.evidence[good.item]
   .filter(evidence=>evidence!==good.recipe.owner+':recipe:'+good.recipe.reference+':out');
 }
 if(defect==='lower-producer')sources.harvests['abcdef:Skyrim.esm']={produce:'59b86:Skyrim.esm',name:'Nirnroot',rank:'novice'};
 if(defect==='lower-recipe') {
  sources.recipes['abcdef:Skyrim.esm']={...copy(sources.recipes['154c6:Thornswood-Content.esp']),out:'59b86:Skyrim.esm'};
  sources.roles.evidence['59b86:Skyrim.esm'].push('Alchemist:recipe:abcdef:Skyrim.esm:out');
 }
 if(defect==='copied-logistics') {
  broken.quests=[broken.quests[2]];broken.quests[0].id='q-new-tailor-logistical-parcel';sources.legacy=[];
 }
 if(defect==='other-logistics') {
  const target=broken.quests[2];target.merchant=copy(source.roster.find(row=>row.bookHold==='whiterun'&&row.role==='Smith'));
  target.gate={profession:'smith',half:'platewright',rank:'master'};
  target.goods=['dca12:Skyrim.esm','dca0f:Skyrim.esm'].map(reference=>{
   const recipe=sources.recipes[reference];return {item:recipe.out,count:3,recipe:{reference,...Object.fromEntries(
    ['owner','half','rank','out','makes','bench','inputItems','needs'].map(key=>[key,recipe[key]]))}};
  });broken.quests=[target];sources.legacy=[];
 }
 assert.throws(()=>validateRankedQuests(broken,sources),/source evidence/,defect);
}
const all=source.legacy.concat(doc.quests);
{
 const parcel=copy(doc),row=parcel.quests[0],sources={...copy(source),gates};
 row.tier='novice';row.cooldownHours=6;row.gate={profession:'smith',half:'edgewright',rank:'novice'};
 row.goods=['15491:Thornswood-Content.esp','f7f43:Skyrim.esm'].map(reference=>{
  const recipe=sources.recipes[reference];return {item:recipe.out,count:recipe.makes,recipe:{reference,...Object.fromEntries(
   ['owner','half','rank','out','makes','bench','inputItems','needs'].map(key=>[key,recipe[key]]))}};
 });parcel.quests=[row];sources.legacy=[];
 assert.doesNotThrow(()=>validateRankedQuests(parcel,sources),'canonical public traded inputs are admitted by actual Smith buy permission');
}
{
 const sources={...copy(source),gates},parcel=copy(doc),row=parcel.quests[5];
 for(const harvest of Object.values(sources.harvests))if(harvest.produce==='59b86:Skyrim.esm')harvest.rank='master';
 const reference='abcdef:Thornswood-Content.esp',recipe={...copy(sources.recipes['154c6:Thornswood-Content.esp']),
  out:'59b86:Skyrim.esm',type:'INGR',inputItems:[{item:'1cd74:Dragonborn.esm',name:'Ash Creep Cluster',type:'INGR',count:1,
   producedBy:'gatherer',producedAt:'master',suppliedBy:'gatherer',suppliedAt:'master',hops:0}]};
 sources.recipes[reference]=recipe;sources.roles.evidence[recipe.out].push('Alchemist:recipe:'+reference+':out');
 row.goods=[row.goods[1],{item:recipe.out,count:1,recipe:{reference,...Object.fromEntries(
  ['owner','half','rank','out','makes','bench','inputItems','needs'].map(key=>[key,recipe[key]]))}}];
 parcel.quests=[row];sources.legacy=[];
 assert.doesNotThrow(()=>validateRankedQuests(parcel,sources),'a Master raw supply can accompany one lower-rank recipe batch with Master inputs');
}
for(const merchant of source.roster.filter(row=>row.bookHold==='whiterun'))for(const tier of ['novice','advanced','expert','master'])
 assert.ok(all.some(row=>row.merchant.reference===merchant.reference&&row.tier===tier),merchant.role+'/'+tier);
for(const kind of ['classes','professions'])for(const key of Object.keys(progression.__thornswoodProgression.TABLE[kind]))
 assert.ok(all.filter(row=>row.gate[kind==='classes'?'classKey':'profession']===key).length>=2,'Two offers for '+kind+'/'+key);
console.log('PASS90 ranked parcels, exact public evidence/role permissions, all24 Whiterun slots and at least two jobs for every class and profession');
