'use strict';
const crypto=require('node:crypto');
function validateScarceHarvest(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='169e46be68e15f8e6954b2ff597844588558ace086e4ac094d4454a21417f8f3'||
    !population||sha(population.loadOrder)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce harvest source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceHarvest};
