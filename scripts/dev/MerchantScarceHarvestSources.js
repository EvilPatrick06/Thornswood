'use strict';
const crypto=require('node:crypto');
function validateScarceHarvest(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='d73a62dace370193312c7f210781ad81cef12ae9b651bb5ffadfc6e860bd3a28'||
    !population||sha(population.loadOrder)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce harvest source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceHarvest};
