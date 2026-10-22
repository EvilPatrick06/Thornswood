'use strict';
const crypto=require('node:crypto');
function validateScarceHarvest(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='ef6b593d2c4340f50b91981aafda7c697658b68c606ea50a7ba0b277c9d9e43f'||
    !population||sha(population.loadOrder)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce harvest source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceHarvest};
