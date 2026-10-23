'use strict';
// Emits a public initial-state document. It never opens or changes a server file.
const crypto=require('node:crypto');
function createAlphaMerchantLedger(roster,population) {
  const fail=()=>{throw new Error('Alpha merchant reset source cannot be verified');};
  const identity=value=>typeof value==='string' && /^([1-9a-f][0-9a-f]{0,5}):[^:/\\\x00-\x1f\x7f]+\.(esm|esp|esl)$/i.test(value);
  const roles=['Smith','Woodworker','Tailor','Enchanter','Cook','Alchemist'];
  const holds={whiterun:'Whiterun',solitude:'Haafingar',riften:'the Rift',markarth:'the Reach',windhelm:'Eastmarch',
    morthal:'Hjaalmarch',dawnstar:'the Pale',winterhold:'Winterhold',falkreath:'Falkreath',ravenrock:'Solstheim'};
  if(!roster || roster.version!==1 || roster.worldMode!=='existing' || !Array.isArray(roster.history) ||
      roster.history.length!==249 || !Array.isArray(roster.merchants) || roster.merchants.length!==60 ||
      !population || !Array.isArray(population.npcs))fail();
  const source=new Map(),history=new Map(),selected=new Map(),coverage=new Set();
  for(const row of population.npcs) {
    if(!row || source.has(row.ref))fail();source.set(row.ref,row);
  }
  for(const pair of roster.history) {
    if(!Array.isArray(pair) || pair.length!==2 || !identity(pair[0]) || !identity(pair[1]) || history.has(pair[0]))fail();
    const row=source.get(pair[0]);if(!row || row.role!=='trader' || row.base!==pair[1])fail();
    history.set(pair[0],pair[1]);
  }
  if(population.npcs.filter(row=>row.role==='trader').length!==249)fail();
  for(const row of roster.merchants) {
    if(!row || !roles.includes(row.role) || !Object.prototype.hasOwnProperty.call(holds,row.bookHold) ||
        holds[row.bookHold]!==row.hold || !history.has(row.reference) || history.get(row.reference)!==row.base || selected.has(row.reference) ||
        source.get(row.reference).hold!==row.hold || source.get(row.reference).keep!==true ||
        coverage.has(row.bookHold+':'+row.role))fail();
    selected.set(row.reference,row);coverage.add(row.bookHold+':'+row.role);
  }
  const entries={};
  for(const [reference,base] of history) entries[reference]=selected.has(reference)?
    {version:1,reference,base,revision:0,purse:250,stock:[],supply:{}}:null;
  // Version 2: the merchant ledger's shape since #2870 (game\gamemode.js, NPC MERCHANT PURSES).
  const doc={version:2,entries};
  doc.sha256=crypto.createHash('sha256').update(JSON.stringify([doc.version,doc.entries])).digest('hex');
  return doc;
}
module.exports={createAlphaMerchantLedger};
if(require.main===module) {
  if(process.argv.length!==3 || process.argv[2]!=='--confirm-discard-alpha')
    throw new Error('Use --confirm-discard-alpha to emit reset data. Claude must stop the matching server before replacing its ledger.');
  process.stdout.write(JSON.stringify(createAlphaMerchantLedger(require('../../game/data/merchant-roster.json'),
    require('../../game/data/npc-population.json')))+'\n');
}
