'use strict';
const crypto=require('node:crypto');
function validateScarceHarvest(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='c304b6901f9c2ba2e2d6410d1bd85d0f4e7404b76fd4720b723685c8e40be16a'||
    !population||sha(population.loadOrder)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce harvest source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceHarvest};
